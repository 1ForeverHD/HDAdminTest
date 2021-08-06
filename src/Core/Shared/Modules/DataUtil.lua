-- LOCAL
local main = require(game.Nanoblox)
local DataUtil = {}
local heartbeat = main.RunService.Heartbeat
local validCharacters = {"a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","1","2","3","4","5","6","7","8","9","0","_","<",">","/","?","@","{","}","[","]","!","(",")","-","=","+","~","#"}
local function isATable(value)
	return type(value) == "table"
end



-- METHODS
function DataUtil.isEqual(v1, v2)
	local valueTypesToString = {
		["Color3"] = true,
		["CFrame"] = true,
		["Vector3"] = true,
	}
	if isATable(v1) and isATable(v2) then
		return main.modules.TableUtil.doTablesMatch(v1, v2)
	elseif valueTypesToString[typeof(v1)] and valueTypesToString[typeof(v2)] then
		v1 = tostring(v1)
		v2 = tostring(v2)
	end
	return v1 == v2
end

function DataUtil.generateUID(length)
	length = length or 5
	local UID = ""
	for i = 1, length do
		local randomCharacter = validCharacters[math.random(1, #validCharacters)]
		UID = UID..randomCharacter
	end
	return UID
end

function DataUtil.getIntFromUID(UID)
	
end

function DataUtil.getUIDFromInt(int)
	
end

function DataUtil.convertTimeStringToSeconds(timeString)
	local totalSeconds = tonumber(timeString) or 0 -- if somebody just specified "100" without any pattern identifiers then by default convert that to seconds
	local patternValues = {
		["s"] = 1, -- seconds
		["m"] = 60, -- minutes
		["h"] = 3600, -- hours
		["d"] = 86400, -- days
		["w"] = 604800, -- weeks
		["o"] = 2628000, -- months
		["y"] = 31540000, -- years
	}
	for value, unit in string.gmatch(timeString, "(%d+)(%a)") do
		totalSeconds += value * patternValues[unit]
	end
	return totalSeconds
end

function DataUtil.color3ToHex(color3)
	local r = math.floor(color3.r*255+.5)
	local g = math.floor(color3.g*255+.5)
	local b = math.floor(color3.b*255+.5)
	return ("%02x%02x%02x"):format(r, g, b)
end

function DataUtil.hexToColor3(hex)
	hex = hex:gsub("#","")
	local r = tonumber("0x"..hex:sub(1,2))
	local g = tonumber("0x"..hex:sub(3,4))
	local b = tonumber("0x"..hex:sub(5,6))
	return Color3.fromRGB(r,g,b)
end

function DataUtil.mergeSettingTables(stateTableToUpdate, valuesToBeApplied)
	for propName, propValue in pairs(valuesToBeApplied) do
		local subTableToUpdate = stateTableToUpdate:get(propName)
		if typeof(subTableToUpdate) == "table" and typeof(propValue) == "table" then
			DataUtil.mergeSettingTables(subTableToUpdate, propValue)
		else
			stateTableToUpdate:set(propName, propValue)
		end
	end
end

function DataUtil.getPathwayDictionaryFromMixedDictionary(propertiesToUpdate)
	-- Some keys may be string pathways (such as {'soundProperties.Volume.Music'} = value) so this converts them into tables (such as {'soundProperties' = {Volume = {Music = value}}})
	if not propertiesToUpdate then
		return {}
	end
	local pathwayDictionary = {}
	for k, value in pairs(propertiesToUpdate) do
		local _, newKey, newValue = DataUtil.getPathwayDictionary(k, value)
		pathwayDictionary[newKey] = newValue
	end
	return pathwayDictionary
end

function DataUtil.getPathwayStringFromTable(pathwayArray)
	if typeof(pathwayArray) ~= "table" then
		return ""
	end
	local pathwayString = table.concat(pathwayArray, ".")
	return pathwayString
end

function DataUtil.getPathwayArrayFromString(pathwayString)
	if typeof(pathwayString) ~= "string" then
		return {}
	end
	local pathwayArray = string.split(pathwayString, ".")
	return pathwayArray
end

function DataUtil.getPathwayDictionary(pathwayString, value)
	-- Some keys may be string pathways (such as {'soundProperties.Volume.Music'} = value) so this converts them into tables (such as {'soundProperties' = {Volume = {Music = value}}})
	pathwayString = (typeof(pathwayString) == "string" and pathwayString) or ""
	local pathwayArray = DataUtil.getPathwayArrayFromString(pathwayString)
	local totalItems = #pathwayArray
	if totalItems > 1 then
		local masterTable = {}
		local bottomTable = masterTable
		local topKey = pathwayArray[1]
		for i, itemKey in pairs(pathwayArray) do
			if i == totalItems then
				bottomTable[itemKey] = value
			elseif i ~= 1 then
				local newBottomTable = {}
				bottomTable[itemKey] = newBottomTable
				bottomTable = newBottomTable
			end
		end
		return {[topKey] = masterTable}, topKey, masterTable
	end
	return {[pathwayString] = value}, pathwayString, value
end

function DataUtil.round(number, decimalPlaces)
	decimalPlaces = decimalPlaces or 0
	return math.round(number * 10^decimalPlaces) * 10^-decimalPlaces
end



return DataUtil