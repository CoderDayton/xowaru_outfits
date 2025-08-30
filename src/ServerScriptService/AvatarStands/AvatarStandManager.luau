--!strict
--[[
	Avatar Stand Manager (Server)
	Manages server-owned avatar stands with persistence and optimized event broadcasting

	ARCHITECTURE:
	- All stands are server-owned (no player ownership)
	- Data persists across server sessions via DataStore
	- Optimized event broadcasting to minimize client traffic
	- Proximity-based event filtering for performance
	- Comprehensive monitoring and metrics

	MAJOR COMPONENTS:
	- AvatarStandData: Handles persistent storage using GameData inheritance
	- ProximityDetection: Manages player interaction zones efficiently (integrated)
	- StandManagement: Core CRUD operations for stands
	- Event Broadcasting: Uses native Signal methods for optimal performance
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Import existing utilities
local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Maid = require(ReplicatedStorage.Packages.Maid)

type Promise<T> = typeof(Promise.new(function() end))

-- Import Avatar Stands modules
local AvatarStandsTypes = require(ReplicatedStorage.AvatarStands.Types)
local AvatarStandsConfig = require(ReplicatedStorage.AvatarStands.Config)
local AvatarStandData = require(script.Parent.AvatarStandData)

type StandConfig = AvatarStandsTypes.StandConfig
type InteractionZone = AvatarStandsTypes.InteractionZone
type StandInteraction = AvatarStandsTypes.StandInteraction
type AvatarDisplay = AvatarStandsTypes.AvatarDisplay
type PersistedStandData = AvatarStandsTypes.PersistedStandData

-- Event names for Signal system (CAREFULLY MANAGED)
local STAND_EVENTS = {
	-- CRITICAL EVENTS (Global broadcast necessary)
	STAND_CREATED = "StandCreated", -- New stand created, all clients need to know
	STAND_REMOVED = "StandRemoved", -- Stand deleted, all clients need to know

	-- OPTIMIZED EVENTS (Proximity/targeted broadcast)
	STAND_UPDATED = "StandUpdated", -- Changes to existing stand, proximity only
	PLAYER_ENTERED_ZONE = "PlayerEnteredZone", -- Player zone events, nearby only
	PLAYER_EXITED_ZONE = "PlayerExitedZone", -- Player zone events, nearby only
	AVATAR_UPDATED = "AvatarUpdated", -- Avatar changes, proximity only

	-- SYSTEM EVENTS (Server-only, no client broadcast)
	SYSTEM_MAINTENANCE = "SystemMaintenance", -- Internal maintenance events
	DATA_BACKUP_COMPLETE = "DataBackupComplete", -- Backup completion
}

local AvatarStandManager = {}
AvatarStandManager.__index = AvatarStandManager

-- Private State (In-Memory Data Structures)
--[[
	MEMORY ARCHITECTURE:

	stands: {[string]: StandConfig}
	- Primary in-memory store for all active stands
	- Key: standId (string) -> Value: StandConfig
	- Memory footprint: ~1KB per stand (estimated)
	- Persistence: Backed up to DataStore every 5 minutes

	interactionZones: {[string]: InteractionZone}
	- Spatial data for proximity detection
	- Key: standId -> Value: zone configuration
	- Updated when stands are moved/created/removed
	- Performance: O(n) proximity checks per heartbeat

	playersInZones: {[number]: {[string]: boolean}}
	- Tracks which players are in which zones
	- Key: userId -> Value: map of standId -> boolean
	- Memory: ~100 bytes per active player
	- Used for enter/exit event detection

	standMaids: {[string]: Maid}
	- Resource cleanup managers per stand
	- Ensures proper cleanup of models, connections, etc.
	- Prevents memory leaks on stand removal
]]
local stands: {[string]: StandConfig} = {}
local interactionZones: {[string]: InteractionZone} = {}
local playersInZones: {[number]: {[string]: boolean}} = {}
local standMaids: {[string]: typeof(Maid.new())} = {}

-- System managers
local avatarStandData: typeof(AvatarStandData.new())
local heartbeatConnection: RBXScriptConnection?
local systemMaid: typeof(Maid.new())

-- Performance metrics
local performanceMetrics = {
	standsCreated = 0,
	standsLoaded = 0,
	proximityChecksPerSecond = 0,
	lastBackupTime = 0,
	memoryUsageKB = 0,
}

function AvatarStandManager.new()
	local self = setmetatable({}, AvatarStandManager)

	-- Initialize system managers
	avatarStandData = AvatarStandData.new()
	systemMaid = Maid.new()

	-- Initialize player tracking
	for _, player in Players:GetPlayers() do
		playersInZones[player.UserId] = {}
	end

	-- Set up player connections using Signal system and wrap with systemMaid
	-- NOTE: Using OnClient for player events is correct here - these are Roblox player events
	systemMaid:GiveTask(Signal.OnServerLocal("PlayerAdded"):Connect(function(player)
		playersInZones[player.UserId] = {}
		print(`👤 Player {player.Name} added to stand tracking`)
	end))

	systemMaid:GiveTask(Signal.OnServerLocal("PlayerRemoving"):Connect(function(player)
		playersInZones[player.UserId] = nil
		-- Note: No longer cleaning up player stands since all stands are server-owned
		print(`👤 Player {player.Name} removed from stand tracking`)
	end))

	-- Load persistent stands from storage
	self:_loadPersistentStands()

	-- Start proximity detection
	self:_startProximityDetection()

	-- Store system maid for cleanup
	self._systemMaid = systemMaid

	print("🎭 AvatarStandManager initialized with persistence and optimization")
	return self
end

function AvatarStandManager:createStand(config: StandConfig): Promise<string>
	return Promise.new(function(resolve, reject)
		-- Validate configuration
		if not AvatarStandsConfig.validateStandId(config.standId) then
			reject("Invalid stand ID: " .. config.standId)
			return
		end

		if stands[config.standId] then
			reject("Stand already exists: " .. config.standId)
			return
		end

		-- Ensure server ownership (remove any player-specific data)
		config.creatorId = nil -- Server-owned stands have no creator
		config.isPersistent = true -- All stands persist by default
		config.version = 1 -- Current data version
		config.permissions.isSystemStand = false -- Not a core system stand
		config.permissions.maintenanceMode = false -- Active by default

		-- Create the physical stand
		local standModel = self:_createStandModel(config)
		if not standModel then
			reject("Failed to create stand model")
			return
		end

		-- Store in memory
		stands[config.standId] = config

		-- Create interaction zone
		local zone: InteractionZone = {
			standId = config.standId,
			range = AvatarStandsConfig.getStandConfig().interactionRange,
			height = 10,
			position = config.position,
			isActive = true,
		}
		interactionZones[config.standId] = zone

		-- Set up cleanup for this stand
		local maid = Maid.new()
		standMaids[config.standId] = maid
		maid:GiveTask(standModel)

		-- Save to persistent storage
		avatarStandData:saveStand(config.standId, config):andThen(function()
			print(`💾 Stand {config.standId} saved to persistent storage`)
		end):catch(function(error)
			warn(`⚠️ Failed to persist stand {config.standId}: {error}`)
		end)

		-- Fire stand creation event (Global - all clients need to know)
		Signal.FireAll(STAND_EVENTS.STAND_CREATED, config)

		-- Update metrics
		performanceMetrics.standsCreated += 1

		resolve(config.standId)
	end)
end

function AvatarStandManager:updateStand(standId: string, changes: {[string]: any}): Promise<StandConfig>
	return Promise.new(function(resolve, reject)
		local existingStand = stands[standId]
		if not existingStand then
			reject("Stand not found: " .. standId)
			return
		end

		-- Apply changes
		for key, value in changes do
			(existingStand :: any)[key] = value
		end

		existingStand.lastUpdated = DateTime.now().UnixTimestamp

		-- Update interaction zone if position changed
		if changes.position then
			local zone = interactionZones[standId]
			if zone then
				zone.position = changes.position
			end
		end

		-- Save changes to persistent storage
		avatarStandData:saveStand(standId, existingStand):catch(function(error)
			warn(`⚠️ Failed to persist stand update {standId}: {error}`)
		end)

		-- Fire stand update event (Proximity - only nearby players)
		self:_fireProximityEvent(STAND_EVENTS.STAND_UPDATED, {standId = standId, changes = changes}, existingStand.position, 80)

		resolve(existingStand)
	end)
end

function AvatarStandManager:removeStand(standId: string): Promise<boolean>
	return Promise.new(function(resolve, reject)
		if not stands[standId] then
			reject("Stand not found: " .. standId)
			return
		end

		-- Clean up resources
		local maid = standMaids[standId]
		if maid then
			maid:DoCleaning()
			standMaids[standId] = nil
		end

		-- Remove from memory structures
		stands[standId] = nil
		interactionZones[standId] = nil

		-- Remove from persistent storage
		avatarStandData:removeStand(standId):catch(function(error)
			warn(`⚠️ Failed to remove stand from persistent storage {standId}: {error}`)
		end)

		-- Fire stand removal event (Global - all clients need to know)
		Signal.FireAll(STAND_EVENTS.STAND_REMOVED, {standId = standId})

		resolve(true)
	end)
end

function AvatarStandManager:getStand(standId: string): StandConfig?
	return stands[standId]
end

function AvatarStandManager:getAllStands(): {[string]: StandConfig}
	return table.clone(stands)
end

-- Get stands by category/filter (replaces player-based filtering)
function AvatarStandManager:getStandsByFilter(filter: {
	isActive: boolean?,
	isSystemStand: boolean?,
	inMaintenanceMode: boolean?,
	withinRange: {position: Vector3, range: number}?,
}?): {StandConfig}
	local filteredStands = {}

	for _, standConfig in stands do
		local includeStand = true

		if filter then
			-- Activity filter
			if filter.isActive ~= nil and standConfig.isActive ~= filter.isActive then
				includeStand = false
			end

			-- System stand filter
			if filter.isSystemStand ~= nil and standConfig.permissions.isSystemStand ~= filter.isSystemStand then
				includeStand = false
			end

			-- Maintenance mode filter
			if filter.inMaintenanceMode ~= nil and standConfig.permissions.maintenanceMode ~= filter.inMaintenanceMode then
				includeStand = false
			end

			-- Range filter
			if filter.withinRange then
				local distance = (standConfig.position - filter.withinRange.position).Magnitude
				if distance > filter.withinRange.range then
					includeStand = false
				end
			end
		end

		if includeStand then
			table.insert(filteredStands, standConfig)
		end
	end

	return filteredStands
end

function AvatarStandManager:setAvatarOnStand(standId: string, avatarData: AvatarDisplay): Promise<boolean>
	return Promise.new(function(resolve, reject)
		local standConfig = stands[standId]
		if not standConfig then
			reject("Stand not found: " .. standId)
			return
		end

		-- Load and position avatar
		self:_loadAvatarOnStand(standId, avatarData):andThen(function()
			-- Save avatar data to persistence
			avatarStandData:saveStand(standId, standConfig, avatarData):catch(function(error)
				warn(`⚠️ Failed to persist avatar data for stand {standId}: {error}`)
			end)

			-- Fire avatar update event (proximity only)
			self:_fireProximityEvent(STAND_EVENTS.AVATAR_UPDATED, {
				standId = standId,
				avatarData = avatarData
			}, standConfig.position, 80)

			resolve(true)
		end):catch(function(error)
			reject(error)
		end)
	end)
end

-- Private Methods

function AvatarStandManager:_createStandModel(config: StandConfig): Model?
	local standModel = Instance.new("Model")
	standModel.Name = "AvatarStand_" .. config.standId

	-- Create base platform
	local platform = Instance.new("Part")
	platform.Name = "Platform"
	platform.Size = Vector3.new(4, 0.5, 4)
	platform.Position = config.position
	platform.Anchored = true
	platform.Material = Enum.Material.Marble
	platform.Color = Color3.fromRGB(200, 200, 200)
	platform.Parent = standModel

	-- Add rounded corners
	local corner = Instance.new("SpecialMesh")
	corner.MeshType = Enum.MeshType.Cylinder
	corner.Parent = platform

	-- Create avatar position marker
	local avatarPosition = Instance.new("Part")
	avatarPosition.Name = "AvatarPosition"
	avatarPosition.Size = Vector3.new(2, 6, 2)
	avatarPosition.Position = config.position + Vector3.new(0, 3.25, 0)
	avatarPosition.Anchored = true
	avatarPosition.CanCollide = false
	avatarPosition.Transparency = 1
	avatarPosition.Parent = standModel

	-- Add lighting
	local pointLight = Instance.new("PointLight")
	pointLight.Brightness = 2
	pointLight.Range = 10
	pointLight.Color = Color3.fromRGB(255, 255, 255)
	pointLight.Parent = platform

	-- Apply lighting preset
	local lightingPreset = AvatarStandsConfig.getLightingPreset(config.displaySettings.lightingPreset)
	pointLight.Color = lightingPreset.ambient
	pointLight.Brightness = lightingPreset.brightness

	standModel.Parent = workspace

	return standModel
end

function AvatarStandManager:_loadAvatarOnStand(standId: string, avatarData: AvatarDisplay): Promise<Model>
	return Promise.new(function(resolve, reject)
		local standModel = workspace:FindFirstChild("AvatarStand_" .. standId)
		if not standModel then
			reject("Stand model not found")
			return
		end

		local avatarPosition = standModel:FindFirstChild("AvatarPosition")
		if not avatarPosition then
			reject("Avatar position not found")
			return
		end

		-- Create avatar model (simplified for starter code)
		local avatarModel = Instance.new("Model")
		avatarModel.Name = "Avatar_" .. avatarData.standName

		-- Create humanoid for avatar
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = avatarModel

		-- Create basic body parts (placeholder)
		local rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2, 1, 1)
		rootPart.Position = avatarPosition.Position
		rootPart.Anchored = true
		rootPart.CanCollide = false
		rootPart.Transparency = 0.5
		rootPart.Color = Color3.fromRGB(100, 150, 200)
		rootPart.Parent = avatarModel

		-- Add rotation animation
		local rotationSpeed = AvatarStandsConfig.getStandConfig().rotationSpeed
		local rotationTween = game:GetService("TweenService"):Create(
			rootPart,
			TweenInfo.new(2 / rotationSpeed, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(360), 0)}
		)
		rotationTween:Play()

		avatarModel.Parent = standModel

		resolve(avatarModel)
	end)
end

function AvatarStandManager:_startProximityDetection()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:_updateProximityDetection()
	end)
end

function AvatarStandManager:_updateProximityDetection()
	local checksThisFrame = 0

	for _, player in Players:GetPlayers() do
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			continue
		end

		local playerPosition = player.Character.HumanoidRootPart.Position
		local playerId = player.UserId
		local currentZones = playersInZones[playerId] or {}

		for standId, zone in interactionZones do
			if not zone.isActive then
				continue
			end

			checksThisFrame += 1
			local distance = (playerPosition - zone.position).Magnitude
			local isInZone = distance <= zone.range
			local wasInZone = currentZones[standId] or false

			if isInZone and not wasInZone then
				-- Player entered zone - fire proximity event
				currentZones[standId] = true
				self:_fireProximityEvent(
					STAND_EVENTS.PLAYER_ENTERED_ZONE,
					{playerId = playerId, standId = standId},
					zone.position,
					50 -- smaller range for zone events
				)
			elseif not isInZone and wasInZone then
				-- Player exited zone - fire proximity event
				currentZones[standId] = nil
				self:_fireProximityEvent(
					STAND_EVENTS.PLAYER_EXITED_ZONE,
					{playerId = playerId, standId = standId},
					zone.position,
					50 -- smaller range for zone events
				)
			end
		end

		playersInZones[playerId] = currentZones
	end

	-- Update performance metrics
	performanceMetrics.proximityChecksPerSecond = checksThisFrame
end

-- Load persistent stands from storage (called on server start)
function AvatarStandManager:_loadPersistentStands()
	print("📀 Loading persistent stands from storage...")

	avatarStandData:loadAllStands():andThen(function(persistentData)
		local loadedCount = 0

		for standId, persistedStand in persistentData do
			-- Restore stand to memory
			stands[standId] = persistedStand.standConfig

			-- Recreate interaction zone
			local zone: InteractionZone = {
				standId = standId,
				range = AvatarStandsConfig.getStandConfig().interactionRange,
				height = 10,
				position = persistedStand.standConfig.position,
				isActive = persistedStand.standConfig.isActive,
			}
			interactionZones[standId] = zone

			-- Recreate physical stand model
			local standModel = self:_createStandModel(persistedStand.standConfig)
			if standModel then
				-- Set up cleanup maid
				local maid = Maid.new()
				standMaids[standId] = maid
				maid:GiveTask(standModel)

				-- Restore avatar if present
				if persistedStand.avatarData then
					self:_loadAvatarOnStand(standId, persistedStand.avatarData):catch(function(error)
						warn(`⚠️ Failed to restore avatar on stand {standId}: {error}`)
					end)
				end

				loadedCount += 1
			else
				warn(`⚠️ Failed to recreate physical model for stand {standId}`)
			end
		end

		performanceMetrics.standsLoaded = loadedCount
		print(`✅ Successfully loaded {loadedCount} persistent stands`)

		-- System loaded successfully (no client broadcast needed)
		print(`ℹ️  System stands loaded: {loadedCount} of {#persistentData} total`)

	end):catch(function(error)
		warn(`❌ Failed to load persistent stands: {error}`)
	end)
end

-- Get comprehensive system statistics
function AvatarStandManager:getSystemStatistics(): {[string]: any}
	local avatarStandDataStats = avatarStandData:getStats()

	return {
		-- Stand statistics
		totalStands = #stands,
		activeStands = #self:getStandsByFilter({isActive = true}),
		systemStands = #self:getStandsByFilter({isSystemStand = true}),
		maintenanceStands = #self:getStandsByFilter({inMaintenanceMode = true}),

		-- Performance metrics
		standsCreated = performanceMetrics.standsCreated,
		standsLoaded = performanceMetrics.standsLoaded,
		proximityChecksPerSecond = performanceMetrics.proximityChecksPerSecond,

		-- Memory usage
		activeZones = #interactionZones,
		trackedPlayers = #playersInZones,
		activeMaids = #standMaids,

		-- Persistence statistics
		persistence = avatarStandDataStats,

		-- System health
		isHealthy = #stands > 0,
		lastHealthCheck = DateTime.now().UnixTimestamp,
	}
end

-- Cleanup and shutdown procedures
function AvatarStandManager:destroy()
	print("🛑 Shutting down AvatarStandManager...")

	-- Stop proximity detection
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	-- Save all stands before shutdown
	avatarStandData:saveAllStands():andThen(function(saveCount)
		print(`💾 Saved {saveCount} stands before shutdown`)
	end):catch(function(error)
		warn(`❌ Failed to save stands during shutdown: {error}`)
	end):await()

	-- Clean up all stand resources
	for standId, maid in standMaids do
		maid:DoCleaning()
	end
	table.clear(standMaids)

	-- Clean up system resources
	if systemMaid then
		systemMaid:DoCleaning()
	end

	-- Clear memory structures
	table.clear(stands)
	table.clear(interactionZones)
	table.clear(playersInZones)

	print("✅ AvatarStandManager shutdown complete")
end

--[[
	FUTURE DEVELOPMENT ROADMAP:

	PHASE 1 - CURRENT (COMPLETE):
	✅ Server-owned stands with persistence
	✅ Optimized event broadcasting
	✅ Data backup and recovery
	✅ Performance monitoring

	PHASE 2 - IMMEDIATE (NEXT 2-4 WEEKS):
	🔄 Advanced UI for stand management
	🔄 Outfit integration with Roblox Catalog API
	🔄 Stand templates and presets
	🔄 Enhanced visual effects and lighting

	PHASE 3 - SHORT TERM (1-2 MONTHS):
	📋 Analytics dashboard for stand usage
	📋 A/B testing framework for stand designs
	📋 Integration with game economy (if applicable)
	📋 Mobile-optimized interaction controls

	PHASE 4 - MEDIUM TERM (2-4 MONTHS):
	📋 Machine learning for outfit recommendations
	📋 Social features (ratings, comments, sharing)
	📋 Advanced permission systems
	📋 Multi-server stand synchronization

	PHASE 5 - LONG TERM (4+ MONTHS):
	📋 VR/AR support for stand interactions
	📋 Integration with external APIs
	📋 Stand marketplace functionality
	📋 Advanced physics and animations
]]

-- Export event names for external use
AvatarStandManager.Events = STAND_EVENTS

--[[
	PROXIMITY DETECTION - Simple and Efficient
	Replaces EventOptimizer with native Signal methods
]]

-- Fire event only to players within proximity range
function AvatarStandManager:_fireProximityEvent(eventName: string, data: any, position: Vector3?, range: number?)
	if not position then
		-- Fallback to global if no position provided
		Signal.FireAll(eventName, data)
		return
	end

	local proximityRange = range or 100
	local nearbyPlayers = {}

	-- Find players within range
	for _, player in Players:GetPlayers() do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local playerPosition = player.Character.HumanoidRootPart.Position
			local distance = (playerPosition - position).Magnitude

			if distance <= proximityRange then
				table.insert(nearbyPlayers, player)
			end
		end
	end

	-- Fire to nearby players only
	for _, player in nearbyPlayers do
		Signal.FireClient(eventName, player, data)
	end
end

-- Export system managers for advanced usage
AvatarStandManager.AvatarStandData = avatarStandData

return AvatarStandManager
