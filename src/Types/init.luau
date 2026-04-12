local _ReflectionService = game:GetService("ReflectionService")
export type map<K = string, V = number> = { [K]: V }
export type list<T = number> = { T }
export type set<T = any> = map<T, true>
export type func<T... = ...any, R... = ...any> = (T...) -> R...

type function fn_constructTableLiteralFromKeysAndTuple(keys: type, fn: type)
	assert(keys:is("union"))
	local tbl = types.newtable()
	local values = fn:parameters().head
	assert(values)

	for i, key in keys:components() do
		local value = values[i]
		tbl:setproperty(key, value)
	end

	return tbl
end

export type constructTableLiteralFromKeysAndTuple<k, v...> = fn_constructTableLiteralFromKeysAndTuple<k, (v...) -> ()>

type function fn_tableFromParallelPacks(keysSig: type, valsSig: type)
	local keys = keysSig:parameters().head
	local vals = valsSig:parameters().head
	assert(keys and vals)

	local out = types.newtable()

	for i, keyType in keys do
		assert(keyType:is("singleton") and typeof(keyType:value()) == "string")
		local valueType = vals[i]
		assert(valueType, "missing value type for key position")
		out:setproperty(keyType, valueType)
	end

	return out
end

export type TableFromParallelPacks<k..., v...> = fn_tableFromParallelPacks<(k...) -> (), (v...) -> ()>

type function fn_unionFromPack(sig: type)
	local params = sig:parameters().head
	assert(params)

	local acc = nil
	for _, t in params do
		acc = if acc == nil then t else types.unionof(acc, t)
	end

	return acc or types.never
end

export type UnionFromPack<t...> = fn_unionFromPack<(t...) -> ()>

type DemoEvent = UnionFromPack<"Spawn", "Despawn", "Update">

local _demoEventOk: DemoEvent = "Spawn"

export type function Partial(object: type)
	local tag = object.tag

	if tag == "union" or tag == "intersection" then
		local result

		for _, component in object:components() do
			if component.tag == "nil" then
				continue
			end
			if result == nil then
				result = component
				continue
			end

			result = types.unionof(result, component)
		end

		return types.optional(result :: type)
	elseif tag == "table" then
		local result = types.newtable()

		for key, prop in object:properties() do
			local partialRead = Partial(prop.read)
			if prop.read ~= prop.write then
				result:setreadproperty(key, partialRead)
				result:setwriteproperty(key, prop.write)
			else
				result:setproperty(key, partialRead)
			end
		end

		return result
	end

	return types.optional(object)
end

export type function IndexedAccess(object: type, key: type)
	if object.tag ~= "table" then
		return types.never
	end

	if not key:is("singleton") or typeof(key:value()) ~= "string" then
		return types.never
	end

	local key_str = key:value()

	for prop_key, prop in object:properties() do
		if prop_key:is("singleton") and prop_key:value() == key_str then
			return prop.read
		end
	end

	return types.never
end

export type function Dissolve(object: type)
	local tag = object.tag

	if tag == "union" then
		local non_nil = {}
		for _, component in object:components() do
			if component.tag == "nil" then
				continue
			end
			table.insert(non_nil, component)
		end

		if #non_nil <= 1 then
			return non_nil[1] or types.never
		else
			return types.unionof(unpack(non_nil))
		end
	elseif tag == "table" then
		local result = types.newtable()

		for key, prop in object:properties() do
			local unpartialedType = Dissolve(prop.read)
			result:setproperty(key, unpartialedType)
		end

		return result
	end

	return object
end

export type function Required(object: type)
	local tag = object.tag

	if tag == "union" then
		local components = {}
		for _, component in object:components() do
			if component.tag == "nil" then
				continue
			end
			table.insert(components, Required(component))
		end

		if #components == 0 then
			return types.never
		elseif #components == 1 then
			return components[1]
		else
			return types.unionof(unpack(components))
		end
	elseif tag == "table" then
		local result = types.newtable()

		for key, prop in object:properties() do
			if prop.read ~= prop.write then
				continue
			end
			local requiredType = Required(prop.read)
			result:setproperty(key, requiredType)
		end

		return result
	end

	if tag == "union" then
		local non_nil = {}
		for _, component in object:components() do
			if component.tag == "nil" then
				continue
			end
			table.insert(non_nil, component)
		end

		if #non_nil == 1 then
			return non_nil[1]
		end
	end

	return object
end

export type function Record(keyType: type, valueType: type)
	local result = types.newtable()
	result:setindexer(keyType, valueType)
	return result
end

export type function Readonly(object: type)
	if object.tag ~= "table" then
		return object
	end

	local result = types.newtable()

	for key, prop in object:properties() do
		result:setreadproperty(key, prop.read)
		result:setwriteproperty(key, types.never)
	end

	return result
end

export type function NonNullable(object: type)
	return Exclude(object, types.singleton(nil))
end



export type function Exclude(unionType: type, excludeType: type)
	if unionType.tag == "table" then
		local result = types.newtable()
		local indexer = unionType:indexer()
		if indexer ~= nil then
			result:setreadindexer(indexer.index, indexer.readresult)
			result:setwriteindexer(indexer.index, indexer.writeresult)
		end

		for key, prop in unionType:properties() do
			local shouldExclude = false

			if excludeType:is("singleton") and typeof(excludeType:value()) == "string" then
				if key:is("singleton") and typeof(key:value()) == "string" and key:value() == excludeType:value() then
					shouldExclude = true
				end
			elseif prop.read == excludeType then
				shouldExclude = true
			end
			if not shouldExclude then
				if prop.read ~= prop.write then
					result:setreadproperty(key, prop.read)
					result:setwriteproperty(key, prop.write)
				else
					result:setproperty(key, prop.read)
				end
			end
		end

		return result
	end

	if unionType.tag ~= "union" then
		return unionType == excludeType and types.never or unionType
	end

	local remaining = {}
	for _, component in unionType:components() do
		if component ~= excludeType then
			table.insert(remaining, component)
		end
	end

	if #remaining == 0 then
		return types.never
	elseif #remaining == 1 then
		return remaining[1]
	else
		return types.unionof(unpack(remaining))
	end
end

export type function Omit(object: type, keys: type, use_find: type?)
	if object.tag ~= "table" then
		return object
	end

	local result = types.newtable()
	local indexer = object:indexer()
	if indexer ~= nil then
		result:setreadindexer(indexer.index, indexer.readresult)
		result:setwriteindexer(indexer.index, indexer.writeresult)
	end

	local key_list = {}
	if keys.tag == "union" then
		for _, component in keys:components() do
			if component:is("singleton") and typeof(component:value()) == "string" then
				table.insert(key_list, component:value())
			end
		end
	elseif keys:is("singleton") and typeof(keys:value()) == "string" then
		table.insert(key_list, keys:value())
	end

	local find_mode = false
	if use_find and use_find:is("singleton") and typeof(use_find:value()) == "boolean" then
		find_mode = use_find:value()
	end

	for key, prop in object:properties() do
		local should_omit = false

		if key:is("singleton") and typeof(key:value()) == "string" then
			local key_str = key:value()
			for _, omit_key in key_list do
				if find_mode then
					if string.find(key_str, omit_key, 1, true) ~= nil then
						should_omit = true
						break
					end
				elseif key_str == omit_key then
					should_omit = true
					break
				end
			end
		end

		if not should_omit then
			if prop.read ~= prop.write then
				result:setreadproperty(key, prop.read)
				result:setwriteproperty(key, prop.write)
			else
				result:setproperty(key, prop.read)
			end
		end
	end

	return result
end

export type function Extract(unionType: type, extractType: type)
	if unionType.tag == "table" then
		local result = types.newtable()

		for key, prop in unionType:properties() do
			local shouldInclude = false

			if extractType:is("singleton") and typeof(extractType:value()) == "string" then
				if key == extractType:value() then
					shouldInclude = true
				end
			elseif prop.read == extractType then
				shouldInclude = true
			end

			if shouldInclude then
				if prop.read ~= prop.write then
					result:setreadproperty(key, prop.read)
					result:setwriteproperty(key, prop.write)
				else
					result:setproperty(key, prop.read)
				end
			end
		end

		return result
	end

	if unionType.tag ~= "union" then
		return unionType == extractType and unionType or types.never
	end

	local matching = {}
	for _, component in unionType:components() do
		if component == extractType then
			table.insert(matching, component)
		end
	end

	if #matching == 0 then
		return types.never
	elseif #matching == 1 then
		return matching[1]
	else
		return types.unionof(unpack(matching))
	end
end

export type function IsOptional(object: type)
	if object.tag ~= "union" then
		return types.singleton(false)
	end

	for _, component in object:components() do
		if component.tag == "nil" then
			return types.singleton(true)
		end
	end

	return types.singleton(false)
end

export type function DeepReadonly(object: type)
	local tag = object.tag

	if tag == "table" then
		local result = types.newtable()

		for key, prop in object:properties() do
			local readonlyProp = DeepReadonly(prop.read)
			result:setreadproperty(key, readonlyProp)
			result:setwriteproperty(key, types.never)
		end

		return result
	elseif tag == "union" then
		local components = {}
		for _, component in object:components() do
			table.insert(components, DeepReadonly(component))
		end

		if #components == 1 then
			return components[1]
		else
			return types.unionof(unpack(components))
		end
	end

	return object
end

--// this is a troll LOL
type function ToCamelCase(s: type)
	if not s:is("singleton") or typeof(s:value()) ~= "string" then
		error("expected string singleton")
	end

	local raw_string = s:value() :: string
	local lowercased = string.gsub(raw_string, "[-. ]", "_")

	local elements = {}
	for part in string.gmatch(lowercased, "[^_]+") do
		table.insert(elements, part)
	end

	if #elements == 0 then
		return types.singleton("")
	end

	local result = {}
	result[1] = string.lower(table.remove(elements, 1) :: string)

	for i = 1, #elements do
		local str = elements[i]
		local first = string.upper(string.sub(str, 1, 1))
		local rest = string.lower(string.sub(str, 2, -1))

		result[i + 1] = first .. rest
	end

	return types.singleton(table.concat(result, ""))
end

type function ToKebabCase(s: type)
	if not s:is("singleton") or typeof(s:value()) ~= "string" then
		error("expected string singleton")
	end

	local raw_string = s:value() :: string
	local kebab = string.gsub(raw_string, "(%u)", function(c)
		return "-" .. string.lower(c)
	end)

	if string.sub(kebab, 1, 1) == "-" then
		kebab = string.sub(kebab, 2)
	end

	return types.singleton(kebab)
end

export type function Pick(object: type, keys: type)
	if object.tag ~= "table" then
		return object
	end

	local result = types.newtable()

	local key_list = {}
	if keys.tag == "union" then
		for _, component in keys:components() do
			if component:is("singleton") and typeof(component:value()) == "string" then
				table.insert(key_list, component:value())
			end
		end
	elseif keys:is("singleton") and typeof(keys:value()) == "string" then
		table.insert(key_list, keys:value())
	end

	for key, prop in object:properties() do
		if key:is("singleton") and typeof(key:value()) == "string" then
			local key_str = key:value()
			for _, pick_key in key_list do
				if key_str == pick_key then
					if prop.read ~= prop.write then
						result:setreadproperty(key, prop.read)
						result:setwriteproperty(key, prop.write)
					else
						result:setproperty(key, prop.read)
					end
					break
				end
			end
		end
	end

	return result
end

-- Merges table types left-to-right; later tables override earlier tables
type function fn_merge(sig: type)
	local tables = sig:parameters().head
	assert(tables)

	local result = types.newtable()

	for _, tableType in tables do
		if not tableType:is("table") then
			return types.newtable()
		end

		local indexer = tableType:indexer()
		if indexer ~= nil then
			result:setreadindexer(indexer.index, indexer.readresult)
			result:setwriteindexer(indexer.index, indexer.writeresult)
		end

		for key, prop in tableType:properties() do
			if prop.read ~= prop.write then
				result:setreadproperty(key, prop.read)
				result:setwriteproperty(key, prop.write)
			else
				result:setproperty(key, prop.read)
			end
		end
	end

	return result
end

export type Merge<t...> = fn_merge<(t...) -> ()>

export type MergeFromSig<sig> = fn_merge<sig>

type tbl_1 = {
    a: number,
    nested: {
        c: boolean
    }
}
type tbl_2 = {
    b: number,
}

type tbl_3 = {
    c: string
}

local function mergeFromSig<Sig>(): MergeFromSig<Sig>
	return nil :: any
end



local _merged_tbl = mergeFromSig<<(tbl_1, tbl_2, tbl_3) -> ()>>()




export type function ValuesOf(object: type)
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

export type function Atomize(object: type)
	if object.tag ~= "table" then
		return types.never
	end
	local result = types.newtable()
	for key, prop in object:properties() do
		local propType = prop.read
		local funcType = types.functionof(types.optional(propType), propType)
		result:setproperty(key, funcType)
	end
	return result
end

export type function PathStrings(tableType: type)
	if tableType.tag ~= "table" then
		return types.never
	end

	local paths = {}
	for key, prop in tableType:properties() do
		if key.tag == "singleton" and typeof(key:value()) == "string" then
			local keyStr = key:value()
			if prop.read.tag == "table" then
				table.insert(paths, types.singleton(keyStr))

				local subPaths = PathStrings(prop.read)
				if subPaths.tag == "union" then
					for _, subPath in subPaths:components() do
						if subPath.tag == "singleton" and typeof(subPath:value()) == "string" then
							table.insert(paths, types.singleton(keyStr .. "/" .. subPath:value()))
						end
					end
				elseif subPaths.tag == "singleton" and typeof(subPaths:value()) == "string" then
					table.insert(paths, types.singleton(keyStr .. "/" .. subPaths:value()))
				elseif subPaths.tag == "never" then
				end
			else
				table.insert(paths, types.singleton(keyStr))
			end
		end
	end

	if #paths == 0 then
		return types.never
	elseif #paths == 1 then
		return paths[1]
	else
		return types.unionof(unpack(paths))
	end
end



export type function IndexByPath(tableType: type, pathType: type)
	if not pathType:is("singleton") or typeof(pathType:value()) ~= "string" then
		return types.never
	end

	local path = pathType:value() :: string
	local segments = string.split(path, "/")

	local current = tableType
	for _, segment in segments do
		if current.tag ~= "table" then
			return types.never
		end

		local found = false
		for key, prop in current:properties() do
			if key:is("singleton") and key:value() == segment then
				current = prop.read
				found = true
				break
			end
		end

		if not found then
			return types.never
		end
	end

	return current
end

type function fn_firstTypeOrDefault(sig: type, defaultType: type)
	local params = sig:parameters().head
	if not params or #params == 0 then
		return defaultType
	end

	return params[1]
end
type function yes(tbl: type)
    if not tbl:is("table") then
        return types.singleton("not table")
    else
        return types.singleton("is table")
    end
end



export type FirstTypeOrDefault<defaultType, t...> = fn_firstTypeOrDefault<(t...) -> (), defaultType>



export type Node<T> = {
	data: T,
	next: Node<T>?,
}

export type NodeWithNext<T, Next...> = {
	data: T,
	next: FirstTypeOrDefault<Node<T>, Next...>?,
}

local _Node: NodeWithNext<number, string> = nil 




type function fn_constructPathTypeTableFromTuple(tableType: type, fn: type)
	local result = types.newtable()
	local paths = fn:parameters().head
	assert(paths)

	for _, path in paths do
		assert(path:is("singleton") and typeof(path:value()) == "string")
		result:setproperty(path, IndexByPath(tableType, path))
	end

	return result
end

export type constructPathTypeTableFromTuple<tableType, p...> = fn_constructPathTypeTableFromTuple<
	tableType,
	(p...) -> ()
>

export type function PathToTypeMap(tableType: type)
	local result = types.newtable()
	local pathStrings = PathStrings(tableType)

	if pathStrings.tag == "never" then
		return result
	end

	if pathStrings.tag == "singleton" then
		local path = pathStrings
		local valueType = IndexByPath(tableType, path)
		result:setproperty(path, valueType)
		return result
	end

	if pathStrings.tag == "union" then
		for _, path in pathStrings:components() do
			if path:is("singleton") and typeof(path:value()) == "string" then
				local valueType = IndexByPath(tableType, path)
				result:setproperty(path, valueType)
			end
		end
	end

	return result
end

type function fn_kleeneSubsetUnionFromStringPack(sig: type, sepType: type)
	local params = sig:parameters().head
	assert(params)

	local separator = ""
	if sepType:is("singleton") and typeof(sepType:value()) == "string" then
		separator = sepType:value()
	end

	local out = {}
	local seen = {}
	local count = #params

	local function push(value: string)
		if seen[value] then
			return
		end
		seen[value] = true
		table.insert(out, types.singleton(value))
	end

	local function visit(index: number, acc: string, hasAny: boolean)
		if index > count then
			push(acc)
			return
		end

		local itemType = params[index]
		assert(itemType:is("singleton") and typeof(itemType:value()) == "string")
		local item = itemType:value() :: string

		visit(index + 1, acc, hasAny)

		local nextAcc: string
		if hasAny and separator ~= "" then
			nextAcc = acc .. separator .. item
		else
			nextAcc = acc .. item
		end

		visit(index + 1, nextAcc, true)
	end

	visit(1, "", false)

	if #out == 0 then
		return types.never
	elseif #out == 1 then
		return out[1]
	else
		return types.unionof(unpack(out))
	end
end

export type KleeneSubsets<s...> = fn_kleeneSubsetUnionFromStringPack<(s...) -> (), "">
export type KleeneSubsetsWithSep<sep, s...> = fn_kleeneSubsetUnionFromStringPack<(s...) -> (), sep>






return 1