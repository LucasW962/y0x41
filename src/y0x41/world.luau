--!strict
--!native
--!optimize 2

const Id = require("./id")
const Log = require("./log")
const Store = require("./store")
const Query = require("./query")

export type map<K = string, V = unknown> = { [K]: V }
export type set<T = unknown> = map<T, true>

export type Entity<T = nil> = Id.Entity<T>
export type Component<T = unknown> = Id.Component<T>

type ComponentId = number | integer
type Signature = set<ComponentId>
type StoreState = Store.Store<unknown>

type WorldState = {
	version: number,
	next_entity_id: number,
	next_component_id: number,
	generations: map<number, number>,
	free_ids: { number },
	dense_entities: { number },
	dense_lookup: map<number, number>,
	signatures: map<number, Signature>,
	stores: map<ComponentId, StoreState>,
	alive_count: number,
}

export type QueryObject<T...> = {
	iter: (self: QueryObject<T...>) -> () -> (Entity?, T...),
	with: (self: QueryObject<T...>, ...Component<unknown>) -> QueryObject<T...>,
	without: (self: QueryObject<T...>, ...Component<unknown>) -> QueryObject<T...>,
	has: (self: QueryObject<T...>, entity: Entity<unknown> | number) -> boolean,
	__iter: (self: QueryObject<T...>) -> () -> (Entity?, T...),
}

export type World = {
	_state: WorldState,

	entity: (self: World, explicit: number?) -> Entity<unknown>,
	component: <T>(self: World) -> Component<T>,

	add: <T>(self: World, entity: Entity<unknown> | number, component: Component<T>) -> (),
	set: <T>(self: World, entity: Entity<unknown> | number, component: Component<T>, value: T) -> (),
	remove: <T>(self: World, entity: Entity<unknown> | number, component: Component<T>) -> (),
	clear: (self: World, entity: Entity<unknown> | number) -> (),
	delete: (self: World, entity: Entity<unknown> | number) -> (),

	get: (self: World, entity: Entity<unknown> | number, ...Component<unknown>) -> ...unknown,
	has: (self: World, entity: Entity<unknown> | number, ...Component<unknown>) -> boolean,
	contains: (self: World, entity: Entity<unknown> | number) -> boolean,
	exists: (self: World, entity: Entity<unknown> | number) -> boolean,
	each: <T>(self: World, component: Component<T>) -> () -> Entity<unknown>?,
	query: <T...>(self: World, ...Component<unknown>) -> QueryObject<T...>,
}

const function to_entity_number(entity: Entity<unknown> | number): number
	return (entity :: unknown) :: number
end

const function to_component_id(component: Component<unknown>): ComponentId
	return (component :: unknown) :: ComponentId
end

const function to_component_id_t<T>(component: Component<T>): ComponentId
	return to_component_id((component :: unknown) :: Component<unknown>)
end

const function components_to_ids(raw_components: { Component<unknown> }): { ComponentId }
	local out = table.create(#raw_components) :: { ComponentId }
	for i = 1, #raw_components do
		out[i] = to_component_id(raw_components[i])
	end
	return out
end

const function mark_structural(state: WorldState)
	state.version += 1
end

const function ensure_signature(state: WorldState, id: number): Signature
	const signature = state.signatures[id]
	if signature ~= nil then
		return signature
	end

	local created: Signature = {}
	state.signatures[id] = created
	return created
end

const function ensure_store(state: WorldState, component_id: ComponentId): StoreState
	const store = state.stores[component_id]
	if store ~= nil then
		return store
	end

	local created: StoreState = Store.new()
	state.stores[component_id] = created
	return created
end

const function contains_impl(state: WorldState, entity: number): boolean
	const id = Id.entity_id(entity)
	const dense = state.dense_lookup[id]
	if dense == nil then
		return false
	end
	return state.dense_entities[dense] == entity
end

const function exists_impl(state: WorldState, entity: number): boolean
	return state.generations[Id.entity_id(entity)] ~= nil
end

const function dense_insert(state: WorldState, entity: number)
	const dense = #state.dense_entities + 1
	const id = Id.entity_id(entity)
	state.dense_entities[dense] = entity
	state.dense_lookup[id] = dense
	ensure_signature(state, id)
	state.alive_count += 1
end

const function entity_auto(state: WorldState): number
	local id: number
	const free_count = #state.free_ids
	if free_count > 0 then
		id = state.free_ids[free_count]
		state.free_ids[free_count] = nil
	else
		state.next_entity_id += 1
		id = state.next_entity_id
	end

	const generation = state.generations[id] or 0
	state.generations[id] = generation

	const entity = Id.entity_combine(id, generation)
	dense_insert(state, entity)
	return entity
end

const function entity_explicit(state: WorldState, explicit: number): number
	const id = Id.entity_id(explicit)
	const generation = Id.entity_generation(explicit)

	const dense = state.dense_lookup[id]
	if dense ~= nil then
		const live = state.dense_entities[dense]
		if live ~= explicit then
			Log.trace("entity id already exists with a different generation")
		end
		return explicit
	end

	const known_generation = state.generations[id]
	if known_generation ~= nil and known_generation ~= generation then
		Log.trace("explicit entity generation does not match world generation")
	end
	state.generations[id] = generation

	if id > state.next_entity_id then
		state.next_entity_id = id
	end

	for i = #state.free_ids, 1, -1 do
		if state.free_ids[i] == id then
			state.free_ids[i] = state.free_ids[#state.free_ids]
			state.free_ids[#state.free_ids] = nil
			break
		end
	end

	dense_insert(state, explicit)
	return explicit
end

const function add_impl(state: WorldState, entity: number, component_id: ComponentId)
	if not contains_impl(state, entity) then
		return
	end

	const id = Id.entity_id(entity)
	const signature = ensure_signature(state, id)
	if signature[component_id] then
		return
	end

	const store = ensure_store(state, component_id)
	Store.set(store, entity, true)
	signature[component_id] = true
	mark_structural(state)
end

const function set_impl(state: WorldState, entity: number, component_id: ComponentId, value: unknown)
	if not contains_impl(state, entity) then
		return
	end

	const id = Id.entity_id(entity)
	const signature = ensure_signature(state, id)
	const inserted = not signature[component_id]

	const store = ensure_store(state, component_id)
	Store.set(store, entity, value)
	if inserted then
		signature[component_id] = true
		mark_structural(state)
	end
end

const function remove_impl(state: WorldState, entity: number, component_id: ComponentId)
	if not contains_impl(state, entity) then
		return
	end

	const id = Id.entity_id(entity)
	const signature = state.signatures[id]
	if signature == nil or not signature[component_id] then
		return
	end

	const store = state.stores[component_id]
	if store ~= nil then
		Store.remove(store, entity)
	end

	signature[component_id] = nil
	mark_structural(state)
end

const function clear_impl(state: WorldState, entity: number)
	if not contains_impl(state, entity) then
		return
	end

	const id = Id.entity_id(entity)
	const signature = state.signatures[id]
	if signature == nil then
		return
	end

	const keys = table.create(8) :: { ComponentId }
	for component_id in signature do
		table.insert(keys, component_id)
	end

	if #keys == 0 then
		return
	end

	for _, component_id in keys do
		const store = state.stores[component_id]
		if store ~= nil then
			Store.remove(store, entity)
		end
		signature[component_id] = nil
	end

	mark_structural(state)
end

const function delete_impl(state: WorldState, entity: number)
	if not contains_impl(state, entity) then
		return
	end

	clear_impl(state, entity)

	const id = Id.entity_id(entity)
	const dense = state.dense_lookup[id] :: number
	const last = #state.dense_entities
	if dense ~= last then
		const moved = state.dense_entities[last]
		state.dense_entities[dense] = moved
		if moved ~= nil then
			state.dense_lookup[Id.entity_id(moved)] = dense
		end
	end
	state.dense_entities[last] = nil
	state.dense_lookup[id] = nil

	local generation = (state.generations[id] or 0) + 1
	if generation >= Id.ENTITY_GENERATION_LIMIT then
		generation = 0
	end
	state.generations[id] = generation
	table.insert(state.free_ids, id)
	state.signatures[id] = nil
	state.alive_count -= 1

	mark_structural(state)
end

const function value_for(state: WorldState, entity: number, component_id: ComponentId): unknown
	const store = state.stores[component_id]
	if store == nil then
		return nil
	end
	return Store.get(store, entity)
end

const function get_impl(state: WorldState, entity: number, ids: { ComponentId }): ...unknown
	if not contains_impl(state, entity) then
		return nil
	end

	const n = #ids
	if n == 0 then
		return
	end

	const values = table.create(n) :: { unknown }
	for i = 1, n do
		values[i] = value_for(state, entity, ids[i])
	end

	return unpack(values, 1, n)
end

const function has_impl(state: WorldState, entity: number, ids: { ComponentId }): boolean
	if not contains_impl(state, entity) then
		return false
	end

	const signature = state.signatures[Id.entity_id(entity)]
	if signature == nil then
		return false
	end

	for _, component_id in ids do
		if not signature[component_id] then
			return false
		end
	end

	return true
end

const function each_impl(state: WorldState, component_id: ComponentId): () -> Entity<unknown>?
	const store = state.stores[component_id]
	if store == nil then
		return function(): Entity<unknown>?
			return nil
		end
	end

	local row = store.size
	return function(): Entity<unknown>?
		while row > 0 do
			const entity = store.dense[row]
			row -= 1
			if entity ~= nil and contains_impl(state, entity) then
				return (entity :: unknown) :: Entity<unknown>
			end
		end
		return nil
	end
end

const function query_impl<T...>(state: WorldState, ids: { ComponentId }): QueryObject<T...>
	return (Query.new(state, ids) :: unknown) :: QueryObject<T...>
end

const function world_entity(self: World, explicit: number?): Entity<unknown>
	const state = self._state
	if explicit == nil then
		return (entity_auto(state) :: unknown) :: Entity<unknown>
	end
	return (entity_explicit(state, explicit) :: unknown) :: Entity<unknown>
end

const function world_component<T>(self: World): Component<T>
	const state = self._state
	state.next_component_id += 1
	return (state.next_component_id :: unknown) :: Component<T>
end

const function world_add<T>(self: World, entity: Entity<unknown> | number, component: Component<T>)
	add_impl(self._state, to_entity_number(entity), to_component_id_t(component))
end

const function world_set<T>(self: World, entity: Entity<unknown> | number, component: Component<T>, value: T)
	set_impl(self._state, to_entity_number(entity), to_component_id_t(component), value)
end

const function world_remove<T>(self: World, entity: Entity<unknown> | number, component: Component<T>)
	remove_impl(self._state, to_entity_number(entity), to_component_id_t(component))
end

const function world_clear(self: World, entity: Entity<unknown> | number)
	clear_impl(self._state, to_entity_number(entity))
end

const function world_delete(self: World, entity: Entity<unknown> | number)
	delete_impl(self._state, to_entity_number(entity))
end

const function world_get(self: World, entity: Entity<unknown> | number, ...: Component<unknown>): ...unknown
	const ids = components_to_ids({ ... })
	return get_impl(self._state, to_entity_number(entity), ids)
end

const function world_has(self: World, entity: Entity<unknown> | number, ...: Component<unknown>): boolean
	const ids = components_to_ids({ ... })
	return has_impl(self._state, to_entity_number(entity), ids)
end

const function world_contains(self: World, entity: Entity<unknown> | number): boolean
	return contains_impl(self._state, to_entity_number(entity))
end

const function world_exists(self: World, entity: Entity<unknown> | number): boolean
	return exists_impl(self._state, to_entity_number(entity))
end

const function world_each<T>(self: World, component: Component<T>): () -> Entity<unknown>?
	return each_impl(self._state, to_component_id_t(component))
end

const function world_query<T...>(self: World, ...: Component<unknown>): QueryObject<T...>
	const ids = components_to_ids({ ... })
	return query_impl<<T...>>(self._state, ids)
end

const function new(): World
	const state: WorldState = {
		version = 0,
		next_entity_id = 0,
		next_component_id = 0,
		generations = {},
		free_ids = {},
		dense_entities = {},
		dense_lookup = {},
		signatures = {},
		stores = {},
		alive_count = 0,
	}

	return {
		_state = state,
		entity = world_entity,
		component = world_component,
		add = world_add,
		set = world_set,
		remove = world_remove,
		clear = world_clear,
		delete = world_delete,
		get = world_get,
		has = world_has,
		contains = world_contains,
		exists = world_exists,
		each = world_each,
		query = world_query,
	}
end

return table.freeze({
	new = new,
})
