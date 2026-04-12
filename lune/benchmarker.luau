const function benchmarker(label: string, iterations: number, fn: () -> ())
	local start = os.clock()
	fn()
	local elapsed = os.clock() - start
	local opsPerSec = if elapsed > 0 then iterations / elapsed else 0
	print(`BENCHMARKER: {label}, TOTAL TIME: {elapsed*1000} MS, OPS: {opsPerSec}`)
end

return benchmarker