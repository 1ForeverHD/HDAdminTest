-- LOCAL
local starterGui = game:GetService("StarterGui")
local IconController = {}
local Icon = require(script.Parent.Icon)
local topbarIcons = {}
local errorStart = "Topbar+ | "



-- FUNCTIONS
function IconController:createIcon(name, imageId, order)
	
	-- Verify data
	local iconDetails = topbarIcons[name]
	if iconDetails then
		warn(("%sFailed to create Icon '%s': an icon already exists under that name."):format(errorStart, name))
		return false
	end
	
	-- Create and record icon
	local icon = Icon.new(name, imageId, order)
	iconDetails = {name = name, icon = icon, order = icon.order}
	topbarIcons[name] = iconDetails
	icon:setOrder(icon.order)
	
	-- Events
	local function updateIcon()
		local iconDetails = topbarIcons[name]
		if not iconDetails then
			warn(("%sFailed to update Icon '%s': icon not found."):format(errorStart, name))
			return false
		end
		iconDetails.order = icon.order or 1
		local orderedIconDetails = {}
		for name, details in pairs(topbarIcons) do
			if details.icon.enabled == true then
				table.insert(orderedIconDetails, details)
			end
		end
		if #orderedIconDetails > 1 then
			table.sort(orderedIconDetails, function(a,b) return a.order < b.order end)
		end
		local startPosition = 104
		local positionIncrement = 44
		if not starterGui:GetCoreGuiEnabled("Chat") then
			startPosition = startPosition - positionIncrement
		end
		for i, details in pairs(orderedIconDetails) do
			local container = details.icon.objects.container
			local iconX = 104 + (i-1)*positionIncrement
			container.Position = UDim2.new(0, iconX, 0, 4)
		end
		return true
	end
	updateIcon()
	icon.updated:Connect(function()
		updateIcon()
	end)
	icon.selected:Connect(function()
		local allIcons = self:getAllIcons()
		for _, otherIcon in pairs(allIcons) do
			if otherIcon ~= icon and otherIcon.deselectWhenOtherIconSelected and otherIcon.toggleStatus == "selected" then
				otherIcon:deselect()
			end
		end
	end)
	
	
	return icon
end

function IconController:getIcon(name)
	local iconDetails = topbarIcons[name]
	if not iconDetails then
		warn(("%sFailed to get Icon '%s': icon not found."):format(errorStart, name))
		return false
	end
	return iconDetails.icon
end

function IconController:getAllIcons()
	local allIcons = {}
	for name, details in pairs(topbarIcons) do
		table.insert(allIcons, details.icon)
	end
	return allIcons
end

function IconController:removeIcon(name)
	local iconDetails = topbarIcons[name]
	if not iconDetails then
		warn(("%sFailed to remove Icon '%s': icon not found."):format(errorStart, name))
		return false
	end
	local icon = iconDetails.icon
	icon:setEnabled(false)
	icon:deselect()
	icon.updated:Fire()
	icon:destroy()
	topbarIcons[name] = nil
	return true
end



return IconController