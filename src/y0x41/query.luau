--!strict
--!native
--!optimize 2

const Id = require("./id")
const Store = require("./store")

type ComponentId = number | integer
type Signature = { [ComponentId]: true }
type StoreState = Store.Store<unknown>

export type WorldView = {
	version: number,
	dense_entities: { number },
	dense_lookup: { [number]: number },
	signatures: { [number]: Signature },
	stores: { [ComponentId]: StoreState },
}

export type QueryState = {
	_state: WorldView,
	_select: { ComponentId },
	_required: { ComponentId },
	_forbidden: { ComponentId }?,
	_cache_version: number?,
	_cache_pivot_dense: { number }?,
	_cache_pivot_size: number?,
}

local QueryMeta = {}
QueryMeta.__index = QueryMeta

-- to silence when dense would return nil
const EMPTY_PIVOT = table.freeze({}) :: { number }

const function push_unique(list: { ComponentId }, value: ComponentId)
	if table.find(list, value) == nil then
		table.insert(list, value)
	end
end

const function contains_entity(state: WorldView, entity: number): boolean
	const dense = state.dense_lookup[Id.entity_id(entity)]
	if dense == nil then
		return false
	end
	return state.dense_entities[dense] == entity
end

const function value_for(state: WorldView, component_id: ComponentId, entity: number): unknown
	const store = state.stores[component_id]
	if store == nil then
		return nil
	end
	return Store.get(store, entity)
end

const function refresh_pivot(query: QueryState): ({ number }, number)
	const state = query._state
	if query._cache_version == state.version then
		const dense = query._cache_pivot_dense
		const size = query._cache_pivot_size
		if dense ~= nil and size ~= nil then
			return dense, size
		end
	end

	const required = query._required
	if #required == 0 then
		query._cache_version = state.version
		query._cache_pivot_dense = state.dense_entities
		query._cache_pivot_size = #state.dense_entities
		return state.dense_entities, #state.dense_entities
	end

	local best_store: StoreState? = nil
	for _, component_id in required do
		const current_store = state.stores[component_id]
		if current_store == nil then
			query._cache_version = state.version
			query._cache_pivot_dense = EMPTY_PIVOT
			query._cache_pivot_size = 0
			return EMPTY_PIVOT, 0
		end

		if best_store == nil or current_store.size < best_store.size then
			best_store = current_store
		end
	end

	if best_store == nil then
		query._cache_version = state.version
		query._cache_pivot_dense = EMPTY_PIVOT
		query._cache_pivot_size = 0
		return EMPTY_PIVOT, 0
	end

	query._cache_version = state.version
	query._cache_pivot_dense = best_store.dense
	query._cache_pivot_size = best_store.size
	return best_store.dense, best_store.size
end

const function matches_entity(query: QueryState, entity: number): boolean
	const state = query._state
	if not contains_entity(state, entity) then
		return false
	end

	const signature = state.signatures[Id.entity_id(entity)]
	if signature == nil then
		return false
	end

	for _, component_id in query._required do
		if not signature[component_id] then
			return false
		end
	end

	const forbidden = query._forbidden
	if forbidden ~= nil then
		for _, component_id in forbidden do
			if signature[component_id] then
				return false
			end
		end
	end

	return true
end

function QueryMeta.iter(self: QueryState): () -> (number?, ...unknown)
	const state = self._state
	const select_ids = self._select
	const count = #select_ids

	const pivot_dense, pivot_size = refresh_pivot(self)
	local row = pivot_size
	const values = table.create(count) :: { unknown }
	return function(): (number?, ...unknown)
		while row > 0 do
			const entity = pivot_dense[row]
			row -= 1
			if entity ~= nil and matches_entity(self, entity) then
				for i = 1, count do
					values[i] = value_for(state, select_ids[i], entity)
				end
				return entity, unpack(values, 1, count)
			end
		end
		return nil
	end
end

function QueryMeta.with(self: QueryState, ...: ComponentId): QueryState
	for _, component_id in { ... } do
		push_unique(self._required, component_id)
	end
	self._cache_version = nil
	self._cache_pivot_dense = nil
	self._cache_pivot_size = nil
	return self
end

function QueryMeta.without(self: QueryState, ...: ComponentId): QueryState
	if self._forbidden == nil then
		self._forbidden = {}
	end

	const forbidden = self._forbidden :: { ComponentId }
	for _, component_id in { ... } do
		push_unique(forbidden, component_id)
	end

	self._cache_version = nil
	self._cache_pivot_dense = nil
	self._cache_pivot_size = nil
	return self
end

function QueryMeta.has(self: QueryState, entity: number): boolean
	return matches_entity(self, entity)
end

QueryMeta.__iter = QueryMeta.iter

const function new(state: WorldView, ids: { ComponentId }): QueryState
	const required = table.clone(ids)
	local query: QueryState = {
		_state = state,
		_select = ids,
		_required = required,
		_forbidden = nil,
		_cache_version = nil,
		_cache_pivot_dense = nil,
		_cache_pivot_size = nil,
	}

	return setmetatable(query, QueryMeta)
end

return table.freeze({
	new = new,
})
