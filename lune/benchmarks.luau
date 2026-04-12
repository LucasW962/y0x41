--!strict
--!native
--!optimize 2

local y0x41 = require("../src/y0x41")
local benchmarker = require("./benchmarker")

local function run_benchmarks()
	local world = y0x41.world()
	local Position = world:component()
	local Velocity = world:component()
	local Health = world:component()

	local N = 50_000
	local ids: { number } = (table.create(N) :: unknown) :: { number }

	benchmarker("spawn entities", N, function()
		for i = 1, N do
			ids[i] = (world:entity() :: unknown) :: number
		end
	end)

	benchmarker("set 3 components", N * 3, function()
		for i = 1, N do
			local id = ids[i]
			world:set(id, Position, { x = i, y = i * 2 })
			world:set(id, Velocity, { x = 1, y = 1 })
			world:set(id, Health, 100)
		end
	end)

	benchmarker("query iteration", N, function()
		local sum = 0
		for _, p, v in world:query(Position, Velocity):iter() do
			sum += (p :: { x: number, y: number }).x + (v :: { x: number, y: number }).x
		end
		if sum <= 0 then
			error("unexpected benchmark sum")
		end
	end)

	benchmarker("get component triple", N, function()
		local sum = 0
		for i = 1, N do
			local p, _, h = world:get(ids[i], Position, Velocity, Health)
			sum += ((p :: { x: number, y: number }).x + (h :: number))
		end
		if sum <= 0 then
			error("unexpected benchmark sum")
		end
	end)

	benchmarker("remove one component", N, function()
		for i = 1, N do
			world:remove(ids[i], Velocity)
		end
	end)

	benchmarker("delete all entities", N, function()
		for i = 1, N do
			world:delete(ids[i])
		end
	end)
end

return {
	run = run_benchmarks,
}
