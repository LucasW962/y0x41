local _ReflectionService = game:GetService("ReflectionService")

export type map<K = string, V = unknown> = { [K]: V }
export type list<T = unknown> = { T }
export type set<T = unknown> = map<T, true>
export type func<T... = ...any, R... = ...any> = (T...) -> R...

type function fn_componentValue(component: type)
	local t = component:readproperty(types.singleton("__T"))
	assert(t, "expected Component<T>")
	return t
end

type function fn_componentValuesTuple(sig: type)
	local params = sig:parameters().head
	assert(params)

	local out = types.newtable()
	for i, component in params do
		out:setproperty(types.singleton(i), fn_componentValue(component))
	end

	return out
end

type function fn_componentValuesUnion(sig: type)
	local params = sig:parameters().head
	assert(params)

	local acc = nil
	for _, component in params do
		local value = fn_componentValue(component)
		acc = if acc == nil then value else types.unionof(acc, value)
	end

	return acc or types.never
end

type function fn_schemaKeys(schema: type)
	if schema.tag ~= "table" then
		return types.never
	end

	local keys = {}
	local indexer = schema:indexer()
	if indexer ~= nil then
		table.insert(keys, indexer.index)
	end

	for key in schema:properties() do
		table.insert(keys, key)
	end

	if #keys == 0 then
		return types.never
	elseif #keys == 1 then
		return keys[1]
	else
		return types.unionof(unpack(keys))
	end
end

type function fn_selectShape(schema: type, keysSig: type)
	if schema.tag ~= "table" then
		return types.never
	end

	local keys = keysSig:parameters().head
	assert(keys)

	local out = types.newtable()
	for _, key in keys do
		assert(key:is("singleton"), "expected singleton table key")
		local value = schema:readproperty(key)
		assert(value, "schema key was missing")
		out:setproperty(key, value)
	end

	return out
end

type function fn_selectValueUnion(schema: type, keysSig: type)
	if schema.tag ~= "table" then
		return types.never
	end

	local keys = keysSig:parameters().head
	assert(keys)

	local acc = nil
	for _, key in keys do
		assert(key:is("singleton"), "expected singleton table key")
		local value = schema:readproperty(key)
		assert(value, "schema key was missing")
		acc = if acc == nil then value else types.unionof(acc, value)
	end

	return acc or types.never
end

type function fn_tableFromParallelPacks(keysSig: type, valsSig: type)
	local keys = keysSig:parameters().head
	local vals = valsSig:parameters().head
	assert(keys and vals)

	local out = types.newtable()
	for i, key in keys do
		assert(key:is("singleton"), "expected singleton key in parallel pack")
		local value = vals[i]
		assert(value, "missing value type for key position")
		out:setproperty(key, value)
	end

	return out
end

type function fn_unionFromPack(sig: type)
	local params = sig:parameters().head
	assert(params)

	local acc = nil
	for _, t in params do
		acc = if acc == nil then t else types.unionof(acc, t)
	end

	return acc or types.never
end

type function fn_firstTypeOrDefault(sig: type, defaultType: type)
	local params = sig:parameters().head
	if not params or #params == 0 then
		return defaultType
	end

	return params[1]
end

type function fn_nonNullable(object: type)
	if object.tag == "nil" then
		return types.never
	end

	if object.tag ~= "union" then
		return object
	end

	local non_nil = {}
	for _, component in object:components() do
		if component.tag ~= "nil" then
			table.insert(non_nil, component)
		end
	end

	if #non_nil == 0 then
		return types.never
	elseif #non_nil == 1 then
		return non_nil[1]
	else
		return types.unionof(unpack(non_nil))
	end
end

type function fn_valuesOf(object: type)
	if object.tag ~= "table" then
		return types.never
	end

	local values = {}
	local indexer = object:indexer()
	if indexer ~= nil then
		table.insert(values, indexer.readresult)
	end

	for _, prop in object:properties() do
		table.insert(values, prop.read)
	end

	if #values == 0 then
		return types.never
	elseif #values == 1 then
		return values[1]
	else
		return types.unionof(unpack(values))
	end
end

type function fn_pick(object: type, keys: type)
	if object.tag ~= "table" then
		return object
	end

	local keep = {}
	if keys.tag == "union" then
		for _, component in keys:components() do
			if component:is("singleton") then
				keep[component:value()] = true
			end
		end
	elseif keys:is("singleton") then
		keep[keys:value()] = true
	end

	local out = types.newtable()
	for key, prop in object:properties() do
		if key:is("singleton") and keep[key:value()] == true then
			if prop.read ~= prop.write then
				out:setreadproperty(key, prop.read)
				out:setwriteproperty(key, prop.write)
			else
				out:setproperty(key, prop.read)
			end
		end
	end

	return out
end

type function fn_omit(object: type, keys: type)
	if object.tag ~= "table" then
		return object
	end

	local omit = {}
	if keys.tag == "union" then
		for _, component in keys:components() do
			if component:is("singleton") then
				omit[component:value()] = true
			end
		end
	elseif keys:is("singleton") then
		omit[keys:value()] = true
	end

	local out = types.newtable()
	local indexer = object:indexer()
	if indexer ~= nil then
		out:setreadindexer(indexer.index, indexer.readresult)
		out:setwriteindexer(indexer.index, indexer.writeresult)
	end

	for key, prop in object:properties() do
		if not (key:is("singleton") and omit[key:value()] == true) then
			if prop.read ~= prop.write then
				out:setreadproperty(key, prop.read)
				out:setwriteproperty(key, prop.write)
			else
				out:setproperty(key, prop.read)
			end
		end
	end

	return out
end

type function fn_merge(sig: type)
	local tables = sig:parameters().head
	assert(tables)

	local out = types.newtable()
	for _, object in tables do
		if object.tag ~= "table" then
			return types.never
		end

		local indexer = object:indexer()
		if indexer ~= nil then
			out:setreadindexer(indexer.index, indexer.readresult)
			out:setwriteindexer(indexer.index, indexer.writeresult)
		end

		for key, prop in object:properties() do
			if prop.read ~= prop.write then
				out:setreadproperty(key, prop.read)
				out:setwriteproperty(key, prop.write)
			else
				out:setproperty(key, prop.read)
			end
		end
	end

	return out
end

export type function Record(keyType: type, valueType: type)
	local out = types.newtable()
	out:setindexer(keyType, valueType)
	return out
end

export type function Partial(object: type)
	if object.tag ~= "table" then
		return types.optional(object)
	end

	local out = types.newtable()
	local indexer = object:indexer()
	if indexer ~= nil then
		out:setreadindexer(indexer.index, types.optional(indexer.readresult))
		out:setwriteindexer(indexer.index, indexer.writeresult)
	end

	for key, prop in object:properties() do
		local partialRead = types.optional(prop.read)
		if prop.read ~= prop.write then
			out:setreadproperty(key, partialRead)
			out:setwriteproperty(key, prop.write)
		else
			out:setproperty(key, partialRead)
		end
	end

	return out
end

export type function Required(object: type)
	if object.tag ~= "table" then
		return fn_nonNullable(object)
	end

	local out = types.newtable()
	local indexer = object:indexer()
	if indexer ~= nil then
		out:setreadindexer(indexer.index, fn_nonNullable(indexer.readresult))
		out:setwriteindexer(indexer.index, indexer.writeresult)
	end

	for key, prop in object:properties() do
		local requiredRead = Required(fn_nonNullable(prop.read))
		if prop.read ~= prop.write then
			out:setreadproperty(key, requiredRead)
			out:setwriteproperty(key, prop.write)
		else
			out:setproperty(key, requiredRead)
		end
	end

	return out
end

export type function Readonly(object: type)
	if object.tag ~= "table" then
		return object
	end

	local out = types.newtable()
	local indexer = object:indexer()
	if indexer ~= nil then
		out:setreadindexer(indexer.index, indexer.readresult)
		out:setwriteindexer(indexer.index, types.never)
	end

	for key, prop in object:properties() do
		out:setreadproperty(key, prop.read)
		out:setwriteproperty(key, types.never)
	end

	return out
end

export type function DeepReadonly(object: type)
	if object.tag == "table" then
		local out = types.newtable()
		local indexer = object:indexer()
		if indexer ~= nil then
			out:setreadindexer(indexer.index, DeepReadonly(indexer.readresult))
			out:setwriteindexer(indexer.index, types.never)
		end

		for key, prop in object:properties() do
			out:setreadproperty(key, DeepReadonly(prop.read))
			out:setwriteproperty(key, types.never)
		end

		return out
	end

	if object.tag == "union" then
		local items = {}
		for _, component in object:components() do
			table.insert(items, DeepReadonly(component))
		end

		if #items == 0 then
			return types.never
		elseif #items == 1 then
			return items[1]
		else
			return types.unionof(unpack(items))
		end
	end

	return object
end

export type function NonNullable(object: type)
	return fn_nonNullable(object)
end

export type function Pick(object: type, keys: type)
	return fn_pick(object, keys)
end

export type function Omit(object: type, keys: type)
	return fn_omit(object, keys)
end

export type SchemaKeys<schema> = fn_schemaKeys<schema>
export type SelectShape<schema, keys...> = fn_selectShape<schema, (keys...) -> ()>
export type SelectValueUnion<schema, keys...> = fn_selectValueUnion<schema, (keys...) -> ()>
export type ZipRecord<k..., v...> = fn_tableFromParallelPacks<(k...) -> (), (v...) -> ()>
export type TableFromParallelPacks<k..., v...> = fn_tableFromParallelPacks<(k...) -> (), (v...) -> ()>
export type UnionFromPack<t...> = fn_unionFromPack<(t...) -> ()>
export type FirstTypeOrDefault<defaultType, t...> = fn_firstTypeOrDefault<(t...) -> (), defaultType>

export type ComponentValue<c> = fn_componentValue<c>
export type ComponentValuesTuple<c...> = fn_componentValuesTuple<(c...) -> ()>
export type ComponentValuesUnion<c...> = fn_componentValuesUnion<(c...) -> ()>

export type ValuesOf<object> = fn_valuesOf<object>
export type Merge<t...> = fn_merge<(t...) -> ()>
export type MergeFromSig<sig> = fn_merge<sig>

export type Keys<object> = keyof<object>
export type RawKeys<object> = rawkeyof<object>
export type IndexedAccess<object, key> = index<object, key>
export type RawIndexedAccess<object, key> = rawget<object, key>
export type WithMetatable<object, metatableType> = setmetatable<object, metatableType>
export type MetatableOf<object> = getmetatable<object>

return 1
