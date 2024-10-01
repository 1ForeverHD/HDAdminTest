-- github repo: https://github.com/AidenJamesYt/hdadmin/tree/main
-- Made by @AidenJamesYt on Roblox & YouTube & GitHub

local main = require(game.Nanoblox)
local Command =	{}



Command.name = script.Name
Command.description = "your going to brazil (in testing)"
Command.aliases	= {"bfling", "sendtobrazil", "onewayticket", "deport"}
Command.opposites = {}
Command.tags = {"fling", "country", "brazil", "funny"}
Command.prefixes = {}
Command.contributors = {82347291, 540881783, 698712377}
Command.blockPeers = false
Command.blockJuniors = false
Command.autoPreview = false
Command.requiresRig = main.enum.HumanoidRigType.R15
Command.revokeRepeats = true
Command.preventRepeats = main.enum.TriStateSetting.Default
Command.cooldown = 2
Command.persistence = main.enum.Persistence.None
Command.args = {"Player"}


function Command.invoke(job, args)
    local player = args[1]
    local root = v.Character:FindFirstChild("HumanoidRootPart")
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://5816432987"
    sound.Volume = 10
    sound.PlayOnRemove = true
    sound.Parent = root
    sound:Destroy()
    task.wait(1.4)
    local vel = Instance.new("BodyVelocity")
    vel.Velocity = CFrame.new(root.Position - Vector3.new(0, 1, 0), root.CFrame.LookVector * 5 + root.Position).LookVector * 1500
    vel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    vel.P = math.huge
    vel.Parent = root
    local smoke = Instance.new("ParticleEmitter")
    smoke.Enabled = true
    smoke.Lifetime = NumberRange.new(0, 3)
    smoke.Rate = 999999
    smoke.RotSpeed = NumberRange.new(0, 20)
    smoke.Rotation = NumberRange.new(0, 360)
    smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.25, 1.25), NumberSequenceKeypoint.new(1, 1.25, 1.25) })
    smoke.Speed = NumberRange.new(1, 1)
    smoke.SpreadAngle = Vector2.new(360, 360)
    smoke.Texture = "rbxassetid://642204234"
    smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0, 0), NumberSequenceKeypoint.new(1, 1, 0) })
    smoke.Parent = root
    service.Debris:AddItem(smoke, 99)
    service.Debris:AddItem(vel, 99)
    hd:Notice("You are going to Brazil! Command in testing, apologies if stuff breaks.")
end
;



return Command
