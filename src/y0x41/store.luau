--!strict
--!native
--!optimize 2

local Id = require("./id")

export type Store<T = unknown> = {
	dense: { number },
	values: { T },
	sparse: { [number]: number },
	size: number,
}

const function new<T>(): Store<T>
	return {
		dense = {},
		values = {},
		sparse = {},
		size = 0,
	}
end

const function index_of<T>(store: Store<T>, entity: number): number?
	local id = Id.entity_id(entity)
	local dense = store.sparse[id]
	if dense == nil then
		return nil
	end

	if store.dense[dense] ~= entity then
		return nil
	end

	return dense
end

const function has<T>(store: Store<T>, entity: number): boolean
	return index_of(store, entity) ~= nil
end

const function get<T>(store: Store<T>, entity: number): T?
	local dense = index_of(store, entity)
	if dense == nil then
		return nil
	end
	return store.values[dense]
end

const function set<T>(store: Store<T>, entity: number, value: T): boolean
	local dense = index_of(store, entity)
	if dense ~= nil then
		store.values[dense] = value
		return false
	end

	local next_index = store.size + 1
	store.size = next_index
	store.dense[next_index] = entity
	store.values[next_index] = value
	store.sparse[Id.entity_id(entity)] = next_index
	return true
end

const function remove<T>(store: Store<T>, entity: number): boolean
	local dense = index_of(store, entity)
	if dense == nil then
		return false
	end

	local id = Id.entity_id(entity)
	local last = store.size
	if dense ~= last then
		local moved = store.dense[last]
		store.dense[dense] = moved
		store.values[dense] = store.values[last]
		if moved ~= nil then
			store.sparse[Id.entity_id(moved)] = dense
		end
	end

	store.dense[last] = nil
	store.values[last] = nil
	store.sparse[id] = nil
	store.size = last - 1
	return true
end

return table.freeze({
	new = new,
	index_of = index_of,
	has = has,
	get = get,
	set = set,
	remove = remove,
})
