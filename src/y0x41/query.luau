--!strict
--!native
--!optimize 2

local Id = require("./id")
local Store = require("./store")

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

const EMPTY_PIVOT = table.freeze({}) :: { number }

const function push_unique(list: { ComponentId }, value: ComponentId)
	if table.find(list, value) == nil then
		table.insert(list, value)
	end
end

const function contains_entity(state: WorldView, entity: number): boolean
	local dense = state.dense_lookup[Id.entity_id(entity)]
	if dense == nil then
		return false
	end
	return state.dense_entities[dense] == entity
end

const function value_for(state: WorldView, component_id: ComponentId, entity: number): unknown
	local store = state.stores[component_id]
	if store == nil then
		return nil
	end
	return Store.get(store, entity)
end

const function refresh_pivot(query: QueryState): ({ number }, number)
	local state = query._state
	if query._cache_version == state.version then
		local dense = query._cache_pivot_dense
		local size = query._cache_pivot_size
		if dense ~= nil and size ~= nil then
			return dense, size
		end
	end

	local required = query._required
	if #required == 0 then
		query._cache_version = state.version
		query._cache_pivot_dense = state.dense_entities
		query._cache_pivot_size = #state.dense_entities
		return state.dense_entities, #state.dense_entities
	end

	local best_store: StoreState? = nil
	for _, component_id in required do
		local current_store = state.stores[component_id]
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
	local state = query._state
	if not contains_entity(state, entity) then
		return false
	end

	local signature = state.signatures[Id.entity_id(entity)]
	if signature == nil then
		return false
	end

	for _, component_id in query._required do
		if not signature[component_id] then
			return false
		end
	end

	local forbidden = query._forbidden
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
	local state = self._state
	local select_ids = self._select
	local count = #select_ids

	local pivot_dense, pivot_size = refresh_pivot(self)
	local row = pivot_size

	if count == 0 then
		return function(): number?
			while row > 0 do
				local entity = pivot_dense[row]
				row -= 1
				if entity ~= nil and matches_entity(self, entity) then
					return entity
				end
			end
			return nil
		end
	end

	local id0 = select_ids[1]
	if count == 1 then
		return function(): (number?, unknown)
			while row > 0 do
				local entity = pivot_dense[row]
				row -= 1
				if entity ~= nil and matches_entity(self, entity) then
					return entity, value_for(state, id0, entity)
				end
			end
			return nil, nil
		end
	end

	local id1 = select_ids[2]
	if count == 2 then
		return function(): (number?, unknown, unknown)
			while row > 0 do
				local entity = pivot_dense[row]
				row -= 1
				if entity ~= nil and matches_entity(self, entity) then
					return entity, value_for(state, id0, entity), value_for(state, id1, entity)
				end
			end
			return nil, nil, nil
		end
	end

	local id2 = select_ids[3]
	if count == 3 then
		return function(): (number?, unknown, unknown, unknown)
			while row > 0 do
				local entity = pivot_dense[row]
				row -= 1
				if entity ~= nil and matches_entity(self, entity) then
					return entity, value_for(state, id0, entity), value_for(state, id1, entity), value_for(state, id2, entity)
				end
			end
			return nil, nil, nil, nil
		end
	end

	local id3 = select_ids[4]
	if count == 4 then
		return function(): (number?, unknown, unknown, unknown, unknown)
			while row > 0 do
				local entity = pivot_dense[row]
				row -= 1
				if entity ~= nil and matches_entity(self, entity) then
					return entity, value_for(state, id0, entity), value_for(state, id1, entity), value_for(state, id2, entity), value_for(state, id3, entity)
				end
			end
			return nil, nil, nil, nil, nil
		end
	end

	local tail = table.create(count - 4)
	return function(): (number?, ...unknown)
		while row > 0 do
			local entity = pivot_dense[row]
			row -= 1
			if entity ~= nil and matches_entity(self, entity) then
				for i = 5, count do
					tail[i - 4] = value_for(state, select_ids[i], entity)
				end
				return entity, value_for(state, id0, entity), value_for(state, id1, entity), value_for(state, id2, entity), value_for(state, id3, entity), unpack(tail)
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

	local forbidden = self._forbidden :: { ComponentId }
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
	local required = table.clone(ids)
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
