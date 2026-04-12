--!strict
--!native
--!optimize 2

const Log = require("./log")

const ENTITY_ID_STRIDE = 2 ^ 24
const ENTITY_GENERATION_LIMIT = 2 ^ 16

const PAIR_NUMBER_OFFSET = 2 ^ 48
const PAIR_NUMBER_SHIFT = 2 ^ 24

const HAS_INTEGER64 = integer ~= nil -- roblox ENV currently does not support integer, luau does
const I64_PAIR_MARK = if HAS_INTEGER64 then integer.fromstring("0x4000000000000000") else nil
const I64_SHIFT_32 = if HAS_INTEGER64 then integer.create(32) else nil
const I64_COMPONENT_MASK = if HAS_INTEGER64 then integer.fromstring("0x0000000000FFFFFF") else nil

export type Entity<T = nil> = { __T: T }
export type Component<T = unknown> = { __T: T }
export type Pair<First = unknown, Second = unknown> = Component<{ first: First, second: Second }>

type EntityHandle = number

const function require_i64(value: integer?, message: string): integer
	if value ~= nil then
		return value
	end

	Log.trace(message)
	return 0
end


const function i64_from_number(value: number): integer
	if not HAS_INTEGER64 then
		Log.trace("integer64 support is unavailable")
	end

	const out = integer.create(value)
	return require_i64(out, "integer64 conversion failed")
end

const function entity_id(entity: EntityHandle): number
	return entity % ENTITY_ID_STRIDE
end

const function entity_generation(entity: EntityHandle): number
	return math.floor(entity / ENTITY_ID_STRIDE)
end

const function entity_combine(id: number, generation: number): EntityHandle
	return id + generation * ENTITY_ID_STRIDE
end

const function entity_next_generation(entity: EntityHandle): EntityHandle
	const id = entity_id(entity)
	local generation = entity_generation(entity) + 1
	if generation >= ENTITY_GENERATION_LIMIT then
		generation = 0
	end
	return entity_combine(id, generation)
end

const function pair(first: Component<unknown> | number, second: Component<unknown> | number): Pair<unknown, unknown>
	const first_number = (first :: unknown) :: number
	const second_number = (second :: unknown) :: number

	if HAS_INTEGER64 then
		const mark = require_i64(I64_PAIR_MARK, "integer64 pair constants are unavailable")
		const shift = require_i64(I64_SHIFT_32, "integer64 pair constants are unavailable")

		const first_i64 = i64_from_number(first_number)
		const second_i64 = i64_from_number(second_number)
		const encoded = integer.bor(mark, integer.lshift(first_i64, shift), second_i64)
		return (encoded :: unknown) :: Pair<unknown, unknown>
	end

	const encoded = second_number + first_number * PAIR_NUMBER_SHIFT + PAIR_NUMBER_OFFSET
	return (encoded :: unknown) :: Pair<unknown, unknown>
end

const function is_pair<T>(id: Component<T> | number): boolean
	const raw = id :: unknown

	if HAS_INTEGER64 and typeof(raw) == "integer" then
		const mark = I64_PAIR_MARK
		if mark ~= nil then
			return integer.btest(raw :: integer, mark)
		end
	end

	if typeof(raw) == "number" then
		return raw >= PAIR_NUMBER_OFFSET
	end

	return false
end

const function pair_first<T>(id: Component<T> | number): Component<unknown>
	const raw = id :: unknown
	if HAS_INTEGER64 and typeof(raw) == "integer" then
		const shift = require_i64(I64_SHIFT_32, "integer64 pair constants are unavailable")
		const mask = require_i64(I64_COMPONENT_MASK, "integer64 pair constants are unavailable")

		const first_i64 = integer.band(integer.rshift(raw :: integer, shift), mask)
		const first_number = integer.tonumber(first_i64)
		return (first_number :: unknown) :: Component<unknown>
	end

	const first_number = math.floor(((raw :: number) - PAIR_NUMBER_OFFSET) / PAIR_NUMBER_SHIFT)
	return (first_number :: unknown) :: Component<unknown>
end

const function pair_second<T>(id: Component<T> | number): Component<unknown>
	const raw = id :: unknown

	if HAS_INTEGER64 and typeof(raw) == "integer" then
		const mask = require_i64(I64_COMPONENT_MASK, "integer64 pair constants are unavailable")

		const second_i64 = integer.band(raw :: integer, mask)
		const second_number = integer.tonumber(second_i64)
		return (second_number :: unknown) :: Component<unknown>
	end

	const second_number = ((raw :: number) - PAIR_NUMBER_OFFSET) % PAIR_NUMBER_SHIFT
	return (second_number :: unknown) :: Component<unknown>
end

return table.freeze({
	ENTITY_ID_STRIDE = ENTITY_ID_STRIDE,
	ENTITY_GENERATION_LIMIT = ENTITY_GENERATION_LIMIT,

	entity_id = entity_id,
	entity_generation = entity_generation,
	entity_combine = entity_combine,
	entity_next_generation = entity_next_generation,

	pair = pair,
	is_pair = is_pair,
	pair_first = pair_first,
	pair_second = pair_second,
})
