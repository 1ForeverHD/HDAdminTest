-- This is responsible for handling player effects which can stack and/or where the original value needs to be remembered

local Agent = {}
Agent.__index = Agent

local main = require(game.Nanoblox)
local Buff = require(script.Buff)
local Janitor = main.modules.Janitor
local sortBuffsByTimeUpdatedFunc = function(buffA, buffB) return buffA.timeUpdated > buffB.timeUpdated end
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local effects = require(script.Buff.Effects)
local bodyUtilPathway = script.Buff.BodyUtil



-- LOCAL FUNCTIONS
local function isSuperiorWeight(baseBuff, toCompareBuff)
	if baseBuff == nil then
		return true
	end
	local baseWeight = baseBuff.weight
	local toCompareWeight = toCompareBuff.weight
	if toCompareWeight > baseWeight or (toCompareWeight == baseWeight and toCompareBuff.timeUpdated > baseBuff.timeUpdated) then
		return true
	end
	return false
end



-- CONSTRUCTOR
function Agent.new(player, reapplyBuffsOnRespawn)
	local self = {}
	setmetatable(self, Agent)
	
	local janitor = Janitor.new()
	self._janitor = janitor
	self.reduceJanitors = {}
	self.buffs = {}
	self.defaultValues = {}
	self.reapplyBuffsOnRespawn = reapplyBuffsOnRespawn
	self.silentlyEndBuffs = false
	self.player = player
	self.groupedBuffs = {}
	self.humanoidDescriptionCount = 0
	self.humanoidDescription = nil
	self.applyingHumanoidDescription = false
	self.remainingHumanoidDescriptionBuffs = 0
	self.destroyed = false

	janitor:add(player.CharacterAdded:Connect(function(char)
		if reapplyBuffsOnRespawn then
			self:clearDefaultValues()
			self:reduceAndApplyEffects()
		else
			self:assassinateBuffs()
		end
	end), "Disconnect")

	janitor:add(players.PlayerRemoving:Connect(function(leavingPlayer)
		if leavingPlayer == player then
			self:destroy()
		end
	end), "Disconnect")

	return self
end



-- METHODS
function Agent:buff(effect, property, weight)
	local buff = Buff.new(effect, property, weight)
	local buffId = buff.buffId
	buff.agent = self
	buff.updated:Connect(function(specificEffect, specificProperty)
		self:reduceAndApplyEffects(specificEffect, specificProperty)
	end)
	self.buffs[buffId] = buff
	return buff
end

function Agent:getBuffs()
	local buffs = {}
	for buffId, buff in pairs(self.buffs) do
		table.insert(buffs, buff)
	end
	table.sort(buffs, sortBuffsByTimeUpdatedFunc)
	return buffs
end

function Agent:getBuffsWithEffect(effect)
	local buffs = {}
	for buffId, buff in pairs(self.buffs) do
		if buff.effect == effect then
			table.insert(buffs, buff)
		end
	end
	table.sort(buffs, sortBuffsByTimeUpdatedFunc)
	return buffs
end

function Agent:updateBuffGroups()
	-- This organises buffs into groups by effect and additonal value
	local groupedBuffs = {}
	self.remainingHumanoidDescriptionBuffs = 0
	for buffId, buff in pairs(self.buffs) do
		local effect = buff.effect
		local group = groupedBuffs[effect]
		if not group then
			group = {}
			groupedBuffs[effect] = group
		end
		local additionalString = tostring(buff.additional)
		local additionalTable = group[additionalString]
		if not additionalTable then
			additionalTable = {}
			group[additionalString] = additionalTable
		end
		table.insert(additionalTable, buff)

		-----------------------------
		local effectModule = effects[effect]
		local effectData = (effectModule and require(effectModule))
		local instancesAndProperties = effectData and effectData(self.player, additionalString)
		if instancesAndProperties then
			for _, group in pairs(instancesAndProperties) do
				local instance = group[1]
				local isAHumanoidDescription = instance.ClassName == "HumanoidDescription"
				if isAHumanoidDescription then
					self.remainingHumanoidDescriptionBuffs += 1
				end
				break
			end
		end
		-----------------------------
	end
	self.groupedBuffs = groupedBuffs
end

function Agent:_getDefaultGroup(effect, instance)
	local key = instance --instance.Name
	if instance.ClassName == "HumanoidDescription" then
		-- HDs constantly change therefore we reference the Humanoid instead to remember the values
		effect = "HumanoidDescription"
		instance = self.player.Character.Humanoid
		key = instance.Name
	end
	local defaultParentGroup = self.defaultValues[effect]
	if defaultParentGroup == nil then
		defaultParentGroup = {}
		self.defaultValues[effect] = defaultParentGroup
	end
	local defaultGroup = defaultParentGroup[key]
	if defaultGroup == nil then
		defaultGroup = {}
		defaultParentGroup[key] = defaultGroup
	end
	return defaultGroup
end

function Agent:clearDefaultValues()
	self.defaultValues = {}
	local buffs = self:getBuffs()
	for _, buff in pairs(buffs) do
		buff.appliedValueTables = {}
	end
	for tweenReference, reduceJanitor in pairs(self.reduceJanitors) do
		reduceJanitor:destroy()
		self.reduceJanitors[tweenReference] = nil
	end
end

function Agent:reduceAndApplyEffects(specificEffect, specificProperty)
	self:updateBuffGroups()
	local humanoidDescription
	local agentCharacter = self.player.Character
	local agentHumanoid = agentCharacter and agentCharacter:FindFirstChild("Humanoid")
	local agentRigType = agentHumanoid and agentHumanoid.RigType.Name

	for effect, additionalTable in pairs(self.groupedBuffs) do
		if not(specificEffect == nil or effect == specificEffect) then
			continue
		end
		
		for additionalString, buffs in pairs(additionalTable) do
			if not(specificProperty == nil or additionalString == specificProperty) then
				continue
			end

			-- This retrieves a nonincremental buff with the greatest weight. If only incremental buffs exist, the one with the highest weight is chosen.
			-- The boss then determines how other buffs will be applied (if at all)
			local bossBuff
			local totalBuffs = #buffs
			for _, buff in pairs(buffs) do
				if (not buff.isDestroyed or totalBuffs <= 1) and (bossBuff == nil or (not buff.incremental and bossBuff.incremental) or (buff.incremental == bossBuff.incremental and isSuperiorWeight(bossBuff, buff))) then
					bossBuff = buff
				end
			end
			if bossBuff == nil then
				for _, buff in pairs(buffs) do
					if isSuperiorWeight(bossBuff, buff) then
						bossBuff = buff
					end
				end
			end

			local isIncremental = bossBuff.incremental
			local isNumerical = type(bossBuff.value) == "number"
			
			-- This determines whether to tween the final value and cancels any other currently tweening values
			local finalValueTweenInfo = bossBuff.tweenInfo
			local tweenReference = tostring(effect)..additionalString
			local reduceTweenJanitor = self.reduceJanitors[tweenReference]
			local forcedBaseValue
			if reduceTweenJanitor then
				reduceTweenJanitor:cleanup()
				local validUntilTime = reduceTweenJanitor.forcedBaseValueValidUntilTime
				if validUntilTime then
					if os.clock() < validUntilTime then
						forcedBaseValue = reduceTweenJanitor.forcedBaseValue
					end
					rawset(reduceTweenJanitor, "forcedBaseValueValidUntilTime", nil)
					rawset(reduceTweenJanitor, "forcedBaseValue", nil)
				end
			elseif tweenReference then
				reduceTweenJanitor = self._janitor:add(Janitor.new(), "Destroy")
				self.reduceJanitors[tweenReference] = reduceTweenJanitor
			end

			-- This retrieves the associated instances then calculates and applies a final value
			-- The default value should only be for only remembering non-numerical values (such as colors, materials, etc)
			-- This is due to numerical based properties having a greater tendency to change on their own (such as Health regeneration)
			-- For numerical values we instead records its 'difference' to deterine the previous value when a buff is removed
			local instancesAndProperties
			local effectModule = effects[effect]
			local effectData = (effectModule and require(effectModule))
			if effectData then
				instancesAndProperties = effectData(self.player, additionalString, bossBuff.value)
			end
			local updatedAccessories = false
			
			for _, group in pairs(instancesAndProperties) do
				
				local instance = group[1]
				local isAHumanoidDescription = instance.ClassName == "HumanoidDescription"
				local propertyName = group[2]
				local propertyValue = forcedBaseValue or (isAHumanoidDescription and humanoidDescription and humanoidDescription[propertyName]) or instance[propertyName]
				local finalValue = propertyValue
				local activeAppliedTables = {}
				local isFinalDestroyedDescBuff = false

				-- We do this as HumanoidDescription properties arent responsive (they are read-only and cant be tweened)
				if isAHumanoidDescription then
					isNumerical = false
					isIncremental = false
				end

				if not isNumerical then
					-- For nonnumerical items we simply 'remember' the original value if the first time setting
					-- This original value is then reapplied when all buffs are removed
					local defaultGroup = self:_getDefaultGroup(effect, instance)
					local defaultAdditionalString = (isAHumanoidDescription and tostring(additionalString) == "nil" and propertyName) or additionalString
					local defaultValue = defaultGroup[defaultAdditionalString]
					if defaultValue == nil then
						defaultGroup[defaultAdditionalString] = propertyValue
						defaultValue = propertyValue
					end
					if bossBuff.isDestroyed then -- if this is the very last buff of that group
						if isAHumanoidDescription then
							if self.remainingHumanoidDescriptionBuffs <= 1 then
								isFinalDestroyedDescBuff = true
							end
						else
							defaultGroup[defaultAdditionalString] = nil
						end
						finalValue = defaultValue
						self.buffs[bossBuff.buffId] = nil
						local BodyUtil = require(bodyUtilPathway)
						BodyUtil.clearFakeBodyParts(self.player, effect, additionalString)
					else
						-- This applies any accessories and tempBuffs associated with the buff
						if agentRigType and not updatedAccessories then
							updatedAccessories = true
							-- Create temp buffs in not already created
							if not bossBuff.appliedTempBuffs and #bossBuff.tempBuffDetails > 0 then
								bossBuff.appliedTempBuffs = true
								for _, tempBuffDetails in pairs(bossBuff.tempBuffDetails) do
									local tempBuff = self:buff(unpack(tempBuffDetails[1]))
									tempBuff.onlyUpdateThisBuff = true
									tempBuff:set(unpack(tempBuffDetails[2]))
									table.insert(bossBuff.tempBuffs, tempBuff)
									tempBuff.onlyUpdateThisBuff = nil
									bossBuff._janitor:add(tempBuff, "destroy")
								end
							end
							-- Remove temp buffs from others (this means if you do ;morph me chair then ;become matt, the character won't still be enitrely invisible)
							for _, buff in pairs(buffs) do
								if not buff.isDestroyed and buff ~= bossBuff and buff.appliedTempBuffs then
									for _, tempBuff in pairs(buff.tempBuffs) do
										tempBuff:destroy()
									end
									buff.tempBuffs = {}
								end
							end
							-- Apply accessories
							for accessory, rigTypePathways in pairs(bossBuff.accessories) do
								local function updateAccessory()
									local finalParent = agentCharacter
									local characterPathway = rigTypePathways[agentRigType]
									for _, name in pairs(characterPathway) do
										finalParent = finalParent:FindFirstChild(name)
										if not finalParent then
											break
										end
									end
									if finalParent then
										local alreadyExists = finalParent:FindFirstChild(accessory.Name)
										if not alreadyExists then
											local accessoryClone = reduceTweenJanitor:add(accessory:Clone(), "Destroy")
											local handle = accessoryClone:FindFirstChild("Handle")
											local forceCanCollide = handle and handle:FindFirstChild("ForceCanCollide")
											accessoryClone.Parent = finalParent
											if forceCanCollide and forceCanCollide.Value == true then
												handle.CanCollide = true
											end
											reduceTweenJanitor:add(accessoryClone.AncestryChanged:Connect(function()
												main.RunService.Heartbeat:Wait()
												if not bossBuff.isDestroyed then
													updateAccessory()
												end
											end), "Disconnect")
										end
									end
								end
								updateAccessory()
							end
						end
						-- This sets the final value to the boss buff value
						local buffValue = bossBuff.value
						if typeof(buffValue) ==  "Instance" then --and buffValue:IsA("HumanoidDescription") then
							buffValue = buffValue[propertyName]
						end
						finalValue = buffValue
					end

				else
					-- For numerical items we instead remember the incremental value, only apply it once, the take it off when the buff is destroyed
					if not isIncremental then
						-- Since 'set' was called, only 1 buff needs to be applied (i.e. the boss buff)
						local previousDifference = 0
						for _, setBuff in pairs(buffs) do
							if not setBuff.incremental then
								local appliedTable = setBuff:_getAppliedValueTable(effect, instance)
								local currentAppliedValue = appliedTable[propertyName]
								if currentAppliedValue then
									previousDifference += currentAppliedValue
									appliedTable[propertyName] = nil
								end
							end
						end
						local bossAppliedTable = bossBuff:_getAppliedValueTable(effect, instance)
						bossAppliedTable[propertyName] = bossBuff.value - propertyValue + previousDifference
						finalValue = bossBuff.value
						table.insert(activeAppliedTables, bossAppliedTable)
					else
						
						for _, incrementalBuff in pairs(buffs) do
							if incrementalBuff.incremental then
								local appliedTable = incrementalBuff:_getAppliedValueTable(effect, instance)
								local currentAppliedValue = appliedTable[propertyName]
								local incrementValue = incrementalBuff.value
								if currentAppliedValue == nil then
									-- If a value has never been applied
									finalValue += incrementValue
									appliedTable[propertyName] = incrementValue
									table.insert(activeAppliedTables, appliedTable)
								elseif currentAppliedValue ~= incrementValue then
									-- If a value was previously applied but has changed
									finalValue -= currentAppliedValue + incrementValue--buff.valueReducer(finalValue)
									appliedTable[propertyName] = incrementValue
									table.insert(activeAppliedTables, appliedTable)
								end
							end
						end
					end

					-- This accounts for destoyed buffs in the finalValue then forgets them
					for _, buff in pairs(buffs) do
						if buff.isDestroyed then
							local appliedTable = buff:_getAppliedValueTable(effect, instance)
							local currentAppliedValue = appliedTable[propertyName]
							if currentAppliedValue then
								finalValue -= currentAppliedValue
							end
							appliedTable[propertyName] = nil
							self.buffs[buff.buffId] = nil
							--
							local BodyUtil = require(bodyUtilPathway)
							BodyUtil.clearFakeBodyParts(self.player, effect, additionalString)
							--
						end
					end

				end

				-- This applies the final value
				if (propertyValue ~= finalValue or forcedBaseValue or isAHumanoidDescription) and not self.silentlyEndBuffs then
					local function updateActiveAppliedTables()
						local difference = finalValue - instance[propertyName]
						for _, appliedTable in pairs(activeAppliedTables) do
							if type(appliedTable[propertyName]) == "number" then
								appliedTable[propertyName] -= difference
							end
						end
					end
					if not finalValueTweenInfo then
						if isAHumanoidDescription then
							self:modifyHumanoidDescription(propertyName, finalValue, isFinalDestroyedDescBuff)
						else
							
							instance[propertyName] = finalValue
						end
						if isNumerical then
							updateActiveAppliedTables()
						end
						
					else
						-- It's important tweens are auto-completed if another effect of same additional value is called before its tween has completed
						local completeTime = os.clock() + finalValueTweenInfo.Time
						local tween = tweenService:Create(instance, finalValueTweenInfo, {[propertyName] = finalValue})
						if isNumerical then
							tween.Completed:Connect(function()
								updateActiveAppliedTables()
							end)
						end
						tween:Play()
						reduceTweenJanitor:add(function()
							if not self.destroyed then
								if tween.PlaybackState ~= Enum.PlaybackState.Completed then
									tween:Pause()
									if type(finalValue) == "number" then
										-- This is really odd behavior.
										rawset(reduceTweenJanitor, "forcedBaseValueValidUntilTime", completeTime)
										rawset(reduceTweenJanitor, "forcedBaseValue", finalValue)
									end
								end
								tween:Destroy()
							end
						end, true)
					end
				end
				
			end
			self.destroyingFinalDescBuff = nil

		end
	end
end

function Agent:modifyHumanoidDescription(propertyName, value, isFinalDestroyedDescBuff)
	-- humanoidDescriptionInstances do this weird thing where they don't always apply, especially when applying as soon as a player respawns
	-- or right after applying another description. The following code is designed to overcome this.
	if self.blockHumanoidDescriptionUpdating then
		return
	end
	self.humanoidDescriptionCount += 1
	local myCount = self.humanoidDescriptionCount
	local humanoid = self.player.Character.Humanoid
	if not self.humanoidDescription then
		self.humanoidDescription = humanoid:GetAppliedDescription()
	end
	self.humanoidDescription[propertyName] = value
	local delayAmount = 0
	if isFinalDestroyedDescBuff then
		-- Tasks are often destroyed before the next one is executed, meaning
		-- the appearance will reset then immidately update again.
		-- We do this to prevent that snapping-jagged feel.
		delayAmount = 0.4
	end
	main.modules.Thread.delay(delayAmount, function()
		if self.humanoidDescriptionCount ~= myCount then
			return
		end
		if self.applyingHumanoidDescription then
			self.reapplyHumanoidDescription = true
			return
		end
		local iterations = 0
		self.applyingHumanoidDescription = true
		local function applyHumanoidDescription()
			local appliedDesc
			local playerHead = self.player.Character:FindFirstChild("Head")
			local facelessHeadPresentOnRemoval = playerHead and playerHead:FindFirstChild("face") == nil
			local originalFace = facelessHeadPresentOnRemoval and self.humanoidDescription and self.humanoidDescription.Face
			humanoid:UnequipTools()
			repeat
				main.RunService.Heartbeat:Wait()
				pcall(function() humanoid:ApplyDescription(self.humanoidDescription) end)
				iterations += 1
				appliedDesc = humanoid and humanoid:GetAppliedDescription()
			until (appliedDesc and self.humanoidDescription and appliedDesc[propertyName] == self.humanoidDescription[propertyName]) or iterations == 10
			if originalFace then
				-- Yes this is ugly, but there's a really frustrating bug with HumanoidDescriptions that breaks the face when a Headless Horseman Head is removed
				self.humanoidDescription.Face = 0
				pcall(function() humanoid:ApplyDescription(self.humanoidDescription) end)
				self.humanoidDescription.Face = originalFace
				pcall(function() humanoid:ApplyDescription(self.humanoidDescription) end)
			end
			if self.reapplyHumanoidDescription then
				self.reapplyHumanoidDescription = nil
				applyHumanoidDescription()
			end
		end
		applyHumanoidDescription()
		----------
		--[[
		if isFinalDestroyedDescBuff then --and not self.destroyingFinalDescBuff then
			self:updateBuffGroups()
			--self.destroyingFinalDescBuff = true
			if self.remainingHumanoidDescriptionBuffs == 0 then
				local defaultGroup = self:_getDefaultGroup("HumanoidDescription", self.humanoidDescription)
				for key, defaultValue in pairs(defaultGroup) do
					self.humanoidDescription[key] = defaultValue
					defaultGroup[key] = nil
				end
				applyHumanoidDescription()
			end
		end--]]
		-----------
		self.blockHumanoidDescriptionUpdating = true
		self:reduceAndApplyEffects()
		self.blockHumanoidDescriptionUpdating = nil
		self.applyingHumanoidDescription = false
		self.humanoidDescription = nil
	end)
end

function Agent:clearBuffs()
	for buffId, buff in pairs(self.buffs) do
		buff:destroy()
	end
end

function Agent:assassinateBuffs()
	self.silentlyEndBuffs = true
	self:clearBuffs()
	self.silentlyEndBuffs = false
end

function Agent:clearBuffsWithEffect(effect)
	for buffId, buff in pairs(self.buffs) do
		if buff.effect == effect then
			buff:destroy()
		end
	end
end

function Agent:destroy()
	self.destroyed = true
	self:clearBuffs()
	self._janitor:destroy()
end
Agent.Destroy = Agent.destroy



return Agent
