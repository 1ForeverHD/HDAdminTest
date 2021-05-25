-- This service is responsible for retrieving assets and replicating them dynamically to clients when requested via the PlayerGui instead
-- of storing everything within ReplicatedStorage to reduce memory consumption and improve join-times.

local DUPLICATE_ASSET_WARNING = "Nanoblox: '%s' is a duplicate asset name! Rename to something unique otherwise assets may be retrieved incorrectly."
local INVALID_CLIENT_ASSET = "Nanoblox: '%s' is not a valid client or shared asset!"
local INVALID_CLIENT_COMMAND_ASSET = "Nanoblox: '%s' is not a valid client asset of command '%s'!"
local INVALID_CLIENT_ASSET_OR_CLIENT_COMMAND_ASSET = "Nanoblox: '%s' is not a valid client command asset (of command '%s'), client asset ot shared asset!"
local INCORRECT_ARRAY = "Nanoblox: 'assetNamesArray' must be an array of string!"
local INVALID_COMMAND = "Nanoblox: '%s' is not a valid command!"

local main = require(game.Nanoblox)
local AssetService = {
    remotes = {}
}
local assetLocationsAndNames = {
    client = {},
    server = {},
    shared = {},
}
local clientPermittedAssets = {}
local serverPermittedAssets = {}
local commandAssets = {}
local assetNameToLocation = {}



-- INIT
function AssetService.init()
    
    -- This checks for duplicate asset names and warns against them
    local function recordAssetName(location, asset)
        local assetName = asset.Name
        local assetDictionary = assetLocationsAndNames[location]
        local alreadyPresent = assetDictionary[assetName]
        if alreadyPresent then
            warn(DUPLICATE_ASSET_WARNING:format(assetName))
            return
        end
        assetDictionary[assetName] = true
        if location == "server" then
            serverPermittedAssets[assetName] = asset
        elseif location == "client" then
            clientPermittedAssets[assetName] = asset
        elseif location == "shared" then
            serverPermittedAssets[assetName] = asset
            clientPermittedAssets[assetName] = asset
        end
        assetNameToLocation[assetName] = location
    end
    
    -- This moves assets out of ReplicatedStorage into a server location called 'AssetStorage' so that they aren't replicated
    local CLIENT_LOCATIONS = {
        "client",
        "shared"
    }
    local assetStorage = Instance.new("Folder")
    assetStorage.Name = "ClientAssetStorage"
    main.assetStorage = assetStorage
    for _, clientLocation in pairs(CLIENT_LOCATIONS) do
        local assetFolder = main[clientLocation].Assets
        local newAssetFolder = Instance.new("Folder")
        newAssetFolder.Name = clientLocation:sub(1,1):upper()..clientLocation:sub(2)
        newAssetFolder.Parent = assetStorage
        for _, child in pairs(assetFolder:GetChildren()) do
            if child.Name == "__forceReplicate" then
                for _, blockedItem in pairs(child:GetChildren()) do
                    recordAssetName(clientLocation, blockedItem)
                    blockedItem.Parent = assetFolder
                end
                child:Destroy()
            else
                recordAssetName(clientLocation, child)
                child.Parent = newAssetFolder
            end
         end
    end

    -- Ensure assets do not have duplicate names between locations
    for _, serverAsset in pairs(main.server.Assets:GetChildren()) do
        recordAssetName("server", serverAsset)
    end
    for assetName, _ in pairs(assetLocationsAndNames.shared) do
        if assetLocationsAndNames.client[assetName] or assetLocationsAndNames.server[assetName] then
            warn(DUPLICATE_ASSET_WARNING:format(assetName))
        end
    end

    -- Transfer command assets to assetStorage
    local commandsFolder = Instance.new("Folder")
    commandsFolder.Name = "Commands"
    commandsFolder.Parent = assetStorage

    local commandNameToParentFolder = {}
    local function transferCommandAsset(commandName, location, asset)
        local commandNameLower = commandName:lower()
        local parentFolder = commandNameToParentFolder[commandNameLower]
        local commandAssetTable = commandAssets[commandNameLower]
        if not parentFolder then
            parentFolder = Instance.new("Folder")
            parentFolder.Name = commandNameLower
            parentFolder.Parent = commandsFolder
            commandNameToParentFolder[commandNameLower] = parentFolder
            commandAssetTable = {
                Client = {},
                Server = {},
                CommandName = commandName,
            }
            commandAssets[commandNameLower] = commandAssetTable
        end
        local locationFolder = parentFolder:FindFirstChild(location)
        if not locationFolder then
            locationFolder = Instance.new("Folder")
            locationFolder.Name = location
            locationFolder.Parent = parentFolder
        end
        commandAssetTable[location][asset.Name] = asset
        asset.Parent = locationFolder
    end

    local function setupCommandAssetStorage(commandModule)
        for _, instance in pairs(commandModule:GetChildren()) do
            if instance:IsA("ModuleScript") then
                local commandName = instance.Name
                for _, serverAsset in pairs(instance:GetChildren()) do
                    if serverAsset.Name == "Client" and serverAsset:IsA("ModuleScript") then
                        for _, clientAsset in pairs(serverAsset:GetChildren()) do
                            transferCommandAsset(commandName, "Client", clientAsset)
                        end
                    else
                        transferCommandAsset(commandName, "Server", serverAsset)
                    end
                end
            else
                setupCommandAssetStorage(instance)
            end
        end
    end
    setupCommandAssetStorage(main.server.Modules.Commands)

    -- Fin
    assetStorage.Parent = main.server.Parent

end



-- START
function AssetService.start()

    local function getClientPermittedAssets(player, assetNamesArray)
        if typeof(assetNamesArray) ~= "table" then
            return false, INCORRECT_ARRAY
        end
        for _, assetName in pairs(assetNamesArray) do
            local asset = clientPermittedAssets[assetName]
            if not asset then
                return false, (INVALID_CLIENT_ASSET):format(tostring(assetName))
            end
        end
        local clonedAssets = {}
        local locations = {}
        for _, assetName in pairs(assetNamesArray) do
            local asset = clientPermittedAssets[assetName]
            local clonedAsset = asset:Clone()
            clonedAsset.Parent = player.PlayerGui
            main.modules.Thread.spawn(function()
                clonedAsset:Destroy()
            end)
            local location = assetNameToLocation[assetName]
            table.insert(clonedAssets, clonedAsset)
            table.insert(locations, location)
        end
        return true, clonedAssets, locations
    end

    local getClientAssets = main.modules.Remote.new("getClientAssets")
    AssetService.remotes.getClientAssets = getClientAssets
    getClientAssets.onServerInvoke = function(player, assetNamesArray)
        local success, assets, locations = getClientPermittedAssets(player, assetNamesArray)
        return success, assets, locations
    end

    local function getCommandClientPermittedAssets(player, commandName, assetNamesArray)
        if typeof(assetNamesArray) ~= "table" then
            return false, INCORRECT_ARRAY
        end
        local tostringCommandName = tostring(commandName)
        local commandAssetTable = commandAssets[tostringCommandName:lower()]
        if not commandAssetTable then
            return false, INVALID_COMMAND:format(tostringCommandName)
        end
        for _, assetName in pairs(assetNamesArray) do
            local asset = commandAssetTable.Client[assetName]
            if not asset then
                return false, (INVALID_CLIENT_COMMAND_ASSET):format(tostring(assetName), tostringCommandName)
            end
        end
        local clonedAssets = {}
        local locations = {}
        for _, assetName in pairs(assetNamesArray) do
            local asset = commandAssetTable.Client[assetName]
            local clonedAsset = asset:Clone()
            clonedAsset.Parent = player.PlayerGui
            main.modules.Thread.spawn(function()
                clonedAsset:Destroy()
            end)
            local location = commandAssetTable.CommandName
            table.insert(clonedAssets, clonedAsset)
            table.insert(locations, location)
        end
        return true, clonedAssets, locations
    end

    local getCommandClientAssets = main.modules.Remote.new("getCommandClientAssets")
    AssetService.remotes.getCommandClientAssets = getCommandClientAssets
    getCommandClientAssets.onServerInvoke = function(player, commandName, assetNamesArray)
        local success, assets, locations = getCommandClientPermittedAssets(player, commandName, assetNamesArray)
        return success, assets, locations
    end

    local getClientCommandAssetOrClientPermittedAssets = main.modules.Remote.new("getClientCommandAssetOrClientPermittedAssets")
    AssetService.remotes.getClientCommandAssetOrClientPermittedAssets = getClientCommandAssetOrClientPermittedAssets
    getClientCommandAssetOrClientPermittedAssets.onServerInvoke = function(player, commandName, assetNamesArray)
        if typeof(assetNamesArray) ~= "table" then
            return false, INCORRECT_ARRAY
        end
        local tostringCommandName = tostring(commandName)
        local commandAssetTable = commandAssets[tostring(commandName):lower()]
        if not commandAssetTable then
            return false, INVALID_COMMAND:format(tostringCommandName)
        end
         local finalAssets = {}
        local finalLocations = {}
        for _, assetName in pairs(assetNamesArray) do
            local success, assets, locations = getCommandClientPermittedAssets(player, commandName, {assetName})
            if not success then
                success, assets, locations = getClientPermittedAssets(player, {assetName})
            end
            if not success then
                return false, (INVALID_CLIENT_ASSET_OR_CLIENT_COMMAND_ASSET):format(tostring(assetName), tostringCommandName)
            end
            table.insert(finalAssets, assets[1])
            table.insert(finalLocations, locations[1])
        end
        return true, finalAssets, finalLocations
    end
    
end



-- METHODS
function AssetService.getAsset(assetName)
    -- Returns a server-permitted asset
    return serverPermittedAssets[assetName]
end

function AssetService.getAssets(assetNamesArray)
    -- Returns an array of server-permitted assets
end

function AssetService.getCommandAsset(assetName)
    -- Returns a command server asset
end

function AssetService.getCommandAssets(assetNamesArray)
    -- Returns an array of command server assets
end

function AssetService.getClientCommandAsset(assetName)
    -- Returns a command client asset
end

function AssetService.getClientCommandAssets(assetNamesArray)
    -- Returns an array of command client assets
end



return AssetService
