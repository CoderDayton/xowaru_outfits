--!strict
--[[
	Avatar Stands Example & Testing Script
	Demonstrates simplified Avatar Stands functionality with single stand type

	Place this script in ServerScriptService to test the Avatar Stands system
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Import modules
local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Maid = require(ReplicatedStorage.Packages.Maid)

-- Import Avatar Stands modules
local AvatarStandManager = require(script.Parent.AvatarStandManager)
local AvatarStandsTypes = require(ReplicatedStorage.AvatarStands.Types)
local AvatarStandsConfig = require(ReplicatedStorage.AvatarStands.Config)

type StandConfig = AvatarStandsTypes.StandConfig
type AvatarDisplay = AvatarStandsTypes.AvatarDisplay

-- Event names for server signals
local STAND_EVENTS = {
	STAND_CREATED = "StandCreated",
	STAND_REMOVED = "StandRemoved",
	AVATAR_UPDATED = "AvatarUpdated",
	PLAYER_ENTERED_ZONE = "PlayerEnteredZone",
	PLAYER_EXITED_ZONE = "PlayerExitedZone",
}

-- Initialize cleanup
local exampleMaid = Maid.new()

-- Create manager instance
local standManager = AvatarStandManager.new()

-- Example configurations for stands
local EXAMPLE_STANDS = {
	{
		standId = "showcase_001",
		position = Vector3.new(10, 5, 0),
		description = "Avatar showcase stand",
	},
	{
		standId = "gallery_001",
		position = Vector3.new(20, 5, 0),
		description = "Outfit gallery stand",
	},
	{
		standId = "exhibition_001",
		position = Vector3.new(30, 5, 0),
		description = "Featured outfit exhibition",
	},
}

-- Example avatar configurations
local EXAMPLE_AVATARS = {
	{
		standId = 1,
		standName = "FashionModel",
		displayName = "Fashion Model",
		outfitId = nil,
	},
	{
		standId = 2,
		standName = "CasualLook",
		displayName = "Casual Look",
		outfitId = nil,
	},
	{
		standId = 3,
		standName = "FormalStyle",
		displayName = "Formal Style",
		outfitId = nil,
	},
}

local AvatarStandsExample = {}

-- Create a stand with the specified configuration
function AvatarStandsExample.createStand(standData: {standId: string, position: Vector3, description: string?}, creatorId: number?)
	local standConfig: StandConfig = {
		standId = standData.standId,
		position = standData.position,
		rotation = Vector3.new(0, 0, 0),
		scale = Vector3.new(1, 1, 1),
		isActive = true,
		creatorId = creatorId,
		permissions = {
			canView = true,
			canEdit = true,
			canInteract = true,
			allowedUsers = nil,
			blockedUsers = nil,
		},
		displaySettings = {
			avatarRotationSpeed = 1.0,
			showNameplate = true,
			showOutfitDetails = true,
			lightingPreset = "Natural",
			cameraDistance = 8,
			cameraHeight = 2,
		},
		createdAt = DateTime.now().UnixTimestamp,
		lastUpdated = DateTime.now().UnixTimestamp,
	}

	print("🎭 Creating stand:", standData.standId, "at", standData.position)
	if standData.description then
		print("📝 Description:", standData.description)
	end

	return standManager:createStand(standConfig)
end

-- Add an avatar to a stand
function AvatarStandsExample.addAvatarToStand(standId: string, avatarData: {standId: number, standName: string, displayName: string, outfitId: number?})
	local avatarDisplay: AvatarDisplay = {
		standId = avatarData.standId,
		standName = avatarData.standName,
		displayName = avatarData.displayName,
		outfitId = avatarData.outfitId,
		accessories = {},
		bodyColors = nil,
		scales = nil,
		lastUpdated = DateTime.now().UnixTimestamp,
	}

	print("👤 Adding avatar to stand:", standId, "Avatar:", avatarData.standName)
	return standManager:setAvatarOnStand(standId, avatarDisplay)
end

-- Set up event listeners for testing
function AvatarStandsExample.setupEventListeners()
	print("🔗 Setting up Avatar Stands event listeners...")

	-- Listen for stand creation events
	exampleMaid:GiveTask(Signal.OnServer(STAND_EVENTS.STAND_CREATED):Connect(function(standConfig)
		print("✅ Stand created:", standConfig.standId, "at position:", standConfig.position)
	end))

	-- Listen for player zone interactions
	exampleMaid:GiveTask(Signal.OnServer(STAND_EVENTS.PLAYER_ENTERED_ZONE):Connect(function(playerId, standId)
		local player = Players:GetPlayerByUserId(playerId)
		if player then
			print("👤 Player", player.Name, "entered stand zone:", standId)
		end
	end))

	exampleMaid:GiveTask(Signal.OnServer(STAND_EVENTS.PLAYER_EXITED_ZONE):Connect(function(playerId, standId)
		local player = Players:GetPlayerByUserId(playerId)
		if player then
			print("👤 Player", player.Name, "exited stand zone:", standId)
		end
	end))

	-- Listen for avatar updates
	exampleMaid:GiveTask(Signal.OnServer(STAND_EVENTS.AVATAR_UPDATED):Connect(function(standId, avatarDisplay)
		print("🎨 Avatar updated on stand:", standId, "Display:", avatarDisplay.standName)
	end))

	-- Listen for stand removal
	exampleMaid:GiveTask(Signal.OnServer(STAND_EVENTS.STAND_REMOVED):Connect(function(standId)
		print("🗑️ Stand removed:", standId)
	end))
end

-- Create all example stands
function AvatarStandsExample.createExampleStands()
	local promises = {}

	for _, standData in ipairs(EXAMPLE_STANDS) do
		table.insert(promises, AvatarStandsExample.createStand(standData))
	end

	return Promise.all(promises)
end

-- Add avatars to the example stands
function AvatarStandsExample.populateStands()
	local promises = {}

	for i, avatarData in ipairs(EXAMPLE_AVATARS) do
		if EXAMPLE_STANDS[i] then
			table.insert(promises, AvatarStandsExample.addAvatarToStand(EXAMPLE_STANDS[i].standId, avatarData))
		end
	end

	return Promise.all(promises)
end

-- Create a grid of stands for testing
function AvatarStandsExample.createStandGrid(centerPosition: Vector3, gridSize: number, spacing: number)
	local promises = {}

	for x = 1, gridSize do
		for z = 1, gridSize do
			local position = centerPosition + Vector3.new(
				(x - (gridSize + 1) / 2) * spacing,
				0,
				(z - (gridSize + 1) / 2) * spacing
			)

			local standData = {
				standId = `grid_stand_{x}_{z}`,
				position = position,
				description = `Grid stand at position ({x}, {z})`,
			}

			table.insert(promises, AvatarStandsExample.createStand(standData))
		end
	end

	return Promise.all(promises)
end

-- Test the complete system
function AvatarStandsExample.runFullTest()
	print("🧪 Starting Avatar Stands Full Test...")

	-- Initialize manager
	standManager:init()

	-- Set up event listeners
	AvatarStandsExample.setupEventListeners()

	-- Create example stands
	AvatarStandsExample.createExampleStands():andThen(function(standIds)
		print("✅ Created", #standIds, "example stands")

		-- Populate stands with avatars
		return AvatarStandsExample.populateStands()
	end):andThen(function()
		print("✅ Populated stands with example avatars")

		-- Create a small grid for additional testing
		local gridPosition = Vector3.new(50, 5, 0)
		return AvatarStandsExample.createStandGrid(gridPosition, 2, 10)
	end):andThen(function(gridStandIds)
		print("✅ Created test grid with", #gridStandIds, "stands")
		print("🎉 Avatar Stands Full Test Completed Successfully!")
	end):catch(function(error)
		warn("❌ Avatar Stands Test Failed:", error)
	end)
end

-- Quick test with minimal setup
function AvatarStandsExample.runQuickTest()
	print("⚡ Starting Avatar Stands Quick Test...")

	-- Initialize manager
	standManager:init()

	-- Create a single test stand
	local testStandData = {
		standId = "quick_test_stand",
		position = Vector3.new(0, 10, 0),
		description = "Quick test stand",
	}

	AvatarStandsExample.createStand(testStandData):andThen(function(standId)
		print("✅ Quick test stand created:", standId)

		-- Add a test avatar
		local testAvatar = {
			standId = 12345,
			standName = "TestAvatar",
			displayName = "Test Avatar",
			outfitId = nil,
		}

		return AvatarStandsExample.addAvatarToStand(standId, testAvatar)
	end):andThen(function()
		print("🎉 Quick Test Completed Successfully!")
	end):catch(function(error)
		warn("❌ Quick Test Failed:", error)
	end)
end

-- Run the example when the script loads
local function main()
	print("🎭 Avatar Stands Example Script Loaded")

	-- Wait a moment for other systems to initialize
	task.wait(2)

	-- Run the quick test by default
	-- Change to runFullTest() for comprehensive testing
	AvatarStandsExample.runQuickTest()
end

-- Start the example
main()

-- Cleanup on server shutdown
game:BindToClose(function()
	exampleMaid:DoCleaning()
end)

return AvatarStandsExample

