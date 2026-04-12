--!strict

local y0x41 = require("../src/y0x41")

const world = y0x41.world()

local Position = world.component<<Vector3>>(world)
local Health = world.component<<number>>(world)
local Name = world.component<<string>>(world)

local entity = world.entity<<number>>(world)
world:set(entity, Position, Vector3.new(2, 4, 6))
world:set(entity, Health, 100)
world:set(entity, Name, "Boss")

local position, health, name = world:get(entity, Position, Health, Name)
local _positionCheck: Vector3 = position
local _healthCheck: number = health
local _nameCheck: string = name

for aliveEntity, qPosition, qHealth in world:query(Position, Health):iter() do
	local _aliveEntityCheck = aliveEntity
	local _queryPositionCheck: Vector3 = qPosition
	local _queryHealthCheck: number = qHealth
end