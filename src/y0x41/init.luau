--!strict
--!native
--!optimize 2

local Id = require("@self/id")
local World = require("@self/world")

return table.freeze({
	world = World.new,
	World = {
		new = World.new,
	},

	pair = Id.pair,
	is_pair = Id.is_pair,
	pair_first = Id.pair_first,
	pair_second = Id.pair_second,

	entity_id = Id.entity_id,
	entity_generation = Id.entity_generation,
	entity_combine = Id.entity_combine,
})
