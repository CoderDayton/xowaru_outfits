--!strict
--[[
	Avatar Stands Data Module

	RESPONSIBILITIES:
	- Manages persistent storage of server-owned avatar stands using GameData base class
	- Provides Avatar Stand specific data operations
	- Handles data serialization for Avatar Stand configurations
	- Ensures data integrity and automatic backup via GameData inheritance

	ARCHITECTURE:
	- Inherits from GameData for robust DataStore operations with caching/backoff
	- Adds Avatar Stand specific methods on top of GameData foundation
	- Follows "Data then Event" approach for system architecture
	- Simplified design avoiding custom DataStore abstractions
]]

-- Import modules
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Promise = require(ReplicatedStorage.Packages.Promise)
local GameData = require(script.Parent.Parent.Modules.GameData)

type Promise<T> = typeof(Promise.new(function() end))

-- Import types
local AvatarStandsTypes = require(ReplicatedStorage.AvatarStands.Types)
type StandConfig = AvatarStandsTypes.StandConfig
type AvatarDisplay = AvatarStandsTypes.AvatarDisplay
type PersistedStandData = AvatarStandsTypes.PersistedStandData
type PersistenceMetadata = AvatarStandsTypes.PersistenceMetadata

-- Constants
local DATASTORE_NAME = "AvatarStands_v1"
local CURRENT_DATA_VERSION = 1

-- Initialize GameData store - inheriting robust persistence foundation
local avatarStandStore = GameData.ForStore(DATASTORE_NAME)

local AvatarStandData = {}
AvatarStandData.__index = AvatarStandData

-- Private state - simplified, leveraging GameData caching
local isShuttingDown = false

function AvatarStandData.new()
	local self = setmetatable({}, AvatarStandData)

	-- Handle server shutdown with GameData's robust saving
	game:BindToClose(function()
		isShuttingDown = true
	end)

	return self
end

--[[
	CORE PERSISTENCE OPERATIONS - Built on GameData Foundation
]]

-- Save a single stand to persistent storage using GameData
function AvatarStandData:saveStand(standId: string, standConfig: StandConfig, avatarData: AvatarDisplay?): Promise<boolean>
	return Promise.new(function(resolve, reject)
		if isShuttingDown then
			reject("Server is shutting down")
			return
		end

		-- Create the persisted data structure
		local persistedData: PersistedStandData = {
			standConfig = standConfig,
			avatarData = avatarData,
			metadata = {
				lastSaved = DateTime.now().UnixTimestamp,
				saveVersion = CURRENT_DATA_VERSION,
				checksum = self:_generateChecksum(standConfig),
				backupCount = 0,
			}
		}

		-- Use GameData's robust Set method with automatic backoff/retry
		avatarStandStore:Set(standId, persistedData):andThen(function()
			resolve(true)
		end):catch(function(err)
			warn(`Failed to save stand {standId}: {err}`)
			reject(err)
		end)
	end)
end

-- Load a single stand from persistent storage using GameData
function AvatarStandData:loadStand(standId: string): Promise<PersistedStandData?>
	return Promise.new(function(resolve, reject)
		-- Use GameData's cached Get method with automatic retries
		avatarStandStore:Get(standId):andThen(function(data)
			if data then
				-- Validate data integrity
				if self:_validateStandData(data) then
					resolve(data)
				else
					warn(`Invalid stand data for {standId}, treating as nil`)
					resolve(nil)
				end
			else
				resolve(nil)
			end
		end):catch(function(err)
			warn(`Failed to load stand {standId}: {err}`)
			reject(err)
		end)
	end)
end

-- Remove a stand from persistent storage using GameData
function AvatarStandData:removeStand(standId: string): Promise<boolean>
	return Promise.new(function(resolve, reject)
		-- Use GameData's robust Remove method
		avatarStandStore:Remove(standId):andThen(function()
			resolve(true)
		end):catch(function(err)
			warn(`Failed to remove stand {standId}: {err}`)
			reject(err)
		end)
	end)
end

-- Load all stands from persistent storage with proper bulk loading
function AvatarStandData:loadAllStands(): Promise<{[string]: PersistedStandData}>
	return Promise.new(function(resolve, reject)
		if isShuttingDown then
			reject("Server is shutting down")
			return
		end

		-- Use GameData's List method to get all keys first
		avatarStandStore:List():andThen(function(standIds)
			if not standIds or #standIds == 0 then
				resolve({})
				return
			end

			-- Load each stand individually using Promise.All for efficiency
			local loadPromises = {}
			for _, standId in ipairs(standIds) do
				local loadPromise = self:loadStand(standId):andThen(function(standData)
					return {standId = standId, data = standData}
				end):catch(function(err)
					warn(`Failed to load stand {standId} during bulk load: {err}`)
					return {standId = standId, data = nil}
				end)
				
				table.insert(loadPromises, loadPromise)
			end

			-- Wait for all stands to load
			Promise.All(loadPromises):andThen(function(results)
				local allStands = {}
				local loadedCount = 0
				local failedCount = 0

				for _, result in ipairs(results) do
					if result.data then
						allStands[result.standId] = result.data
						loadedCount += 1
					else
						failedCount += 1
					end
				end

				print(`📋 Bulk loaded {loadedCount} stands successfully, {failedCount} failed`)
				resolve(allStands)
			end):catch(function(err)
				warn(`Bulk load failed: {err}`)
				reject(err)
			end)
		end):catch(function(err)
			warn(`Failed to list stands for bulk loading: {err}`)
			reject(err)
		end)
	end)
end

--[[
	AVATAR STAND SPECIFIC UTILITIES
]]

-- Update avatar data for an existing stand
function AvatarStandData:updateAvatarData(standId: string, avatarData: AvatarDisplay): Promise<boolean>
	return Promise.new(function(resolve, reject)
		-- Use GameData's Update method for atomic operations
		avatarStandStore:Update(standId, function(existingData)
			if existingData and existingData.standConfig then
				existingData.avatarData = avatarData
				existingData.metadata.lastSaved = DateTime.now().UnixTimestamp
				return existingData
			end
			return nil -- Don't create if doesn't exist
		end):andThen(function(result)
			if result then
				resolve(true)
			else
				reject("Stand not found or invalid")
			end
		end):catch(function(err)
			reject(err)
		end)
	end)
end

-- Get cached stand data without DataStore call
function AvatarStandData:getCachedStand(standId: string): PersistedStandData?
	-- Leverage GameData's built-in caching
	return avatarStandStore:GetCached(standId)
end

-- Invalidate cache for a specific stand
function AvatarStandData:invalidateStandCache(standId: string)
	avatarStandStore:InvalidateCache(standId)
end

--[[
	PRIVATE UTILITIES - Simplified
]]

-- Generate checksum for data integrity (simplified)
function AvatarStandData:_generateChecksum(standConfig: StandConfig): string
	-- Simple checksum based on key properties
	local keyData = {
		standConfig.position and tostring(standConfig.position) or "",
		standConfig.standType or "",
		standConfig.zoneName or "",
	}
	return string.format("%x", string.len(table.concat(keyData)))
end

-- Validate stand data structure
function AvatarStandData:_validateStandData(data: any): boolean
	if type(data) ~= "table" then
		return false
	end

	if not data.standConfig or type(data.standConfig) ~= "table" then
		return false
	end

	if not data.metadata or type(data.metadata) ~= "table" then
		return false
	end

	return true
end

-- Get system statistics
function AvatarStandData:getStats(): {[string]: any}
	return {
		dataStoreName = DATASTORE_NAME,
		dataVersion = CURRENT_DATA_VERSION,
		isShuttingDown = isShuttingDown,
		-- GameData provides its own caching stats internally
	}
end

return AvatarStandData