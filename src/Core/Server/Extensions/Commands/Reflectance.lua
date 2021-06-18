local main = require(game.Nanoblox)
local Command =	{}



Command.name = script.Name
Command.description = "Changes the reflectance of the players body"
Command.aliases	= {"ref"}
Command.opposites = {}
Command.tags = {"Appearance"}
Command.prefixes = {}
Command.contributors = {82347291}
Command.blockPeers = false
Command.blockJuniors = false
Command.autoPreview = false
Command.requiresRig = main.enum.HumanoidRigType.None
Command.revokeRepeats = true
Command.preventRepeats = main.enum.TriStateSetting.False
Command.cooldown = 0
Command.persistence = main.enum.Persistence.UntilPlayerRespawns
Command.args = {"Player", "Number"}

function Command.invoke(task, args)
	local _, number = unpack(args)
	if number then
		task:buffPlayer("BodyReflectance"):set(number)
	end
end



return Command