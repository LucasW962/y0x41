local _ReflectionService = game:GetService("ReflectionService")

export type map<K = string, V = unknown> = { [K]: V }
export type list<T = unknown> = { T }

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
	local keys = keysSig:parameters().head
	assert(keys)

	local out = types.newtable()
	for _, key in keys do
		assert(key:is("singleton") and typeof(key:value()) == "string")
		local value = schema:readproperty(key)
		assert(value, "schema key was missing")
		out:setproperty(key, value)
	end

	return out
end

type function fn_selectValueUnion(schema: type, keysSig: type)
	local keys = keysSig:parameters().head
	assert(keys)

	local acc = nil
	for _, key in keys do
		assert(key:is("singleton") and typeof(key:value()) == "string")
		local value = schema:readproperty(key)
		assert(value, "schema key was missing")
		acc = if acc == nil then value else types.unionof(acc, value)
	end

	return acc or types.never
end

type function fn_zipRecord(keysSig: type, valsSig: type)
	local keys = keysSig:parameters().head
	local vals = valsSig:parameters().head
	assert(keys and vals)

	local out = types.newtable()
	for i, key in keys do
		assert(key:is("singleton") and typeof(key:value()) == "string")
		local value = vals[i]
		assert(value, "missing value type for key position")
		out:setproperty(key, value)
	end

	return out
end

export type SchemaKeys<schema> = fn_schemaKeys<schema>
export type SelectShape<schema, keys...> = fn_selectShape<schema, (keys...) -> ()>
export type SelectValueUnion<schema, keys...> = fn_selectValueUnion<schema, (keys...) -> ()>
export type ZipRecord<k..., v...> = fn_zipRecord<(k...) -> (), (v...) -> ()>
export type ComponentValue<c> = fn_componentValue<c>
export type ComponentValuesTuple<c...> = fn_componentValuesTuple<(c...) -> ()>
export type ComponentValuesUnion<c...> = fn_componentValuesUnion<(c...) -> ()>

return 1
