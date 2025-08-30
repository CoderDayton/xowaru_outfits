--!strict
--[[
	Avatar Stands Initialization Script
	Initializes the Avatar Stands system on the server with simplified single stand type
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Import modules
local Signal = require(ReplicatedStorage.Packages.Signal)
local Maid = require(ReplicatedStorage.Packages.Maid)

-- Import the Avatar Stand Manager
local AvatarStandManager = require(script.Parent.AvatarStandManager)
local AvatarStandsTypes = require(ReplicatedStorage.AvatarStands.Types)

type StandConfig = AvatarStandsTypes.StandConfig
type AvatarDisplay = AvatarStandsTypes.AvatarDisplay

-- Initialize cleanup
local serverMaid = Maid.new()

-- Initialize the manager
local standManager = AvatarStandManager.new()

-- Event names for server signals
local STAND_EVENTS = {
	STAND_CREATED = "StandCreated",
	PLAYER_ENTERED_ZONE = "PlayerEnteredZone",
	PLAYER_EXITED_ZONE = "PlayerExitedZone",
}

-- Example: Create a demo stand for testing
local function createDemoStand()
	local demoConfig: StandConfig = {
		standId = "demo_stand_001",
		position = Vector3.new(0, 5, 0),
		rotation = Vector3.new(0, 0, 0),
		scale = Vector3.new(1, 1, 1),
		isActive = true,
		creatorId = nil, -- No specific creator for demo
		permissions = {
			canView = true,
			canEdit = false,
			canInteract = true,
			allowedUsers = nil,
			blockedUsers = nil,
		},
		displaySettings = {
			avatarRotationSpeed = 0.5,
			showNameplate = true,
			showOutfitDetails = true,
			lightingPreset = "Natural",
			cameraDistance = 8,
			cameraHeight = 2,
		},
		createdAt = DateTime.now().UnixTimestamp,
		lastUpdated = DateTime.now().UnixTimestamp,
	}

	standManager:createStand(demoConfig):andThen(function(standId)
		print("✅ Demo stand created successfully:", standId)

		-- Add a demo avatar to the stand
		local demoAvatar: AvatarDisplay = {
			standId = 1,
			standName = "DemoAvatar",
			displayName = "Demo Character",
			outfitId = nil,
			accessories = {},
			bodyColors = nil,
			scales = nil,
			lastUpdated = DateTime.now().UnixTimestamp,
		}

		return standManager:setAvatarOnStand(standId, demoAvatar)
	end):andThen(function()
		print("✅ Demo avatar added to stand")
	end):catch(function(error)
		warn("❌ Failed to create demo stand:", error)
	end)
end

-- Set up event listeners using Signal.OnServer
serverMaid:GiveTask(Signal.OnServer(STAND_EVENTS.STAND_CREATED):Connect(function(config)
	print("🎭 Stand created:", config.standId)
end))

serverMaid:GiveTask(Signal.OnServer(STAND_EVENTS.PLAYER_ENTERED_ZONE):Connect(function(playerId, standId)
	local player = game.Players:GetPlayerByUserId(playerId)
	if player then
		print("👤 Player", player.Name, "entered stand zone:", standId)
	end
end))

serverMaid:GiveTask(Signal.OnServer(STAND_EVENTS.PLAYER_EXITED_ZONE):Connect(function(playerId, standId)
	local player = game.Players:GetPlayerByUserId(playerId)
	if player then
		print("👤 Player", player.Name, "exited stand zone:", standId)
	end
end))

-- Create demo stand after a short delay
task.wait(2)
createDemoStand()

print("🎭 Avatar Stands System Initialized")

-- Export the manager for other scripts to use
_G.AvatarStandManager = standManager

-- Cleanup on server shutdown
game:BindToClose(function()
	serverMaid:DoCleaning()
	if standManager then
		standManager:destroy()
	end
end)

return standManager
