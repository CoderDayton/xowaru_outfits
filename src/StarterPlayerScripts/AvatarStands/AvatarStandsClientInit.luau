--!strict
--[[
	Avatar Stands Client Initialization
	Initializes the client-side Avatar Stands system
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- Import modules
local Signal = require(ReplicatedStorage.Packages.Signal)
local Maid = require(ReplicatedStorage.Packages.Maid)

-- Wait for game to load
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Wait for character
LocalPlayer.CharacterAdded:Wait()

-- Import the client manager
local AvatarStandClient = require(script.Parent.AvatarStandClient)

-- Initialize cleanup
local clientMaid = Maid.new()

-- Event names for client signals
local CLIENT_EVENTS = {
	INTERACTION_ZONE_ENTERED = "InteractionZoneEntered",
	INTERACTION_ZONE_EXITED = "InteractionZoneExited",
	UI_STATE_CHANGED = "UIStateChanged",
}

-- Initialize the client
local clientManager = AvatarStandClient.new()

-- Set up event listeners using Signal.OnClient
clientMaid:GiveTask(Signal.OnLocal(CLIENT_EVENTS.INTERACTION_ZONE_ENTERED, function(standId)
	print("🎭 Entered interaction zone for stand:", standId)
end))

clientMaid:GiveTask(Signal.OnLocal(CLIENT_EVENTS.INTERACTION_ZONE_EXITED, function(standId)
	print("🎭 Exited interaction zone for stand:", standId)
end))

clientMaid:GiveTask(Signal.OnLocal(CLIENT_EVENTS.UI_STATE_CHANGED, function(newState)
	print("🎮 UI State changed:", newState.currentView, "Active Stand:", newState.activeStandId)
end))

print("🎭 Avatar Stands Client Initialized")

-- Export for global access
_G.AvatarStandClient = clientManager

-- Cleanup on player leaving
LocalPlayer.AncestryChanged:Connect(function()
	clientMaid:DoCleaning()
end)

return clientManager
