--!strict
--!native
--!optimize 2

const PREFIX = "Y0X41: "

export type Logger = {
	format: (message: unknown) -> string,
	trace: (message: unknown, level: number?) -> never,
	panic: (message: unknown, level: number?) -> never,
	assert: (condition: boolean, message: unknown, level: number?) -> (),
}

const function format(message: unknown): string
	return `{PREFIX} {tostring(message)}`
end

const function panic(message: unknown, level: number?): never
	const stack = debug.traceback(format(message), (level or 1) + 1)
	error(stack, 0)
end

const function trace(message: unknown, level: number?): never
	return panic(message, (level or 1) + 1)
end

const function assert(condition: boolean, message: unknown, level: number?)
	if not condition then
		trace(message, (level or 1) + 1)
	end
end

return table.freeze({
	format = format,
	panic = panic,
	trace = trace,
	assert = assert,
})
