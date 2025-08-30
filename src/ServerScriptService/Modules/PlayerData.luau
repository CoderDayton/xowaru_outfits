--!strict
--[[
    PlayerData.luau
    PlayerData module for managing player profiles
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(ReplicatedStorage.Packages.Signal)
local GameData = require(script.Parent.GameData)
local ProfileMigration = require(script.Parent.ProfileMigration)

export type Profile = {
	SchemaVersion: number,
	JoinCount: number,
	LastSeen: number,
}

local PlayerData = {}

local Profiles = GameData.ForStore("PlayerProfiles")
local SessionStore: DataStore = DataStoreService:GetDataStore("PlayerSessions")
local Telemetry = require(script.Parent.Telemetry)

local DEFAULT_PROFILE: Profile = {
	SchemaVersion = 0,
	JoinCount = 0,
	LastSeen = 0,
}

local function sessionKey(userId: number): string
	return "session_" .. tostring(userId)
end

function PlayerData.Load(player: Player): any
	return Promise.new(function(resolve, reject)
		local uid = player.UserId
		local skey = sessionKey(uid)

		-- Acquire lock
		local okLock, locked = pcall(SessionStore.GetAsync, SessionStore, skey)
		if okLock and locked and locked.locked then
			reject("Profile in use")
			return
		end
		local okSet = pcall(SessionStore.SetAsync, SessionStore, skey, {
			locked = true,
			server = game.JobId,
			time = os.time(),
		})
		if not okSet then
			reject("Failed to lock session")
			return
		end

		-- Load profile (no cache on first read)
		Profiles:Get(tostring(uid), 0)
			:andThen(function(raw: any)
				local prof: Profile = raw or table.clone(DEFAULT_PROFILE)
				prof = ProfileMigration.Migrate(prof)
				prof.JoinCount += 1

				if prof.JoinCount == 1 then
					Telemetry.Add("NewPlayerJoined")
				end

				prof.LastSeen = os.time()
				return Profiles:Set(tostring(uid), prof):andThen(function()
					return prof
				end)
			end)
			:andThen(resolve)
			:catch(function(err)
				pcall(SessionStore.RemoveAsync, SessionStore, skey)
				reject(err)
			end)
	end)
end

function PlayerData.Save(player: Player, profile: Profile): any
	return Profiles:Set(tostring(player.UserId), profile)
end

function PlayerData.Get(player: Player): any
	return Profiles:Get(tostring(player.UserId), 60) -- cached
end

function PlayerData.Release(player: Player): ()
	local key = sessionKey(player.UserId)
	-- Best-effort unlock; do not block shutdown paths
	pcall(SessionStore.RemoveAsync, SessionStore, key)
end

-- Initialize the module and connect to player events
function PlayerData.Init()
	Players.PlayerAdded:Connect(function(player)
		PlayerData.Load(player)
			:andThen(function(profile)
				Signal.FireServerLocal("PlayerAdded", player, profile)
				Signal.FireClient("PlayerAdded", player, profile)
				Telemetry.Add("ProfileLoaded")
			end)
			:catch(function(err)
				warn("Failed to load profile for player " .. player.UserId .. ": " .. tostring(err))
                Telemetry.Add("ProfileLoadFailed")
			end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Signal.FireServerLocal("PlayerRemoving", player)
		Signal.FireClient("PlayerRemoving", player)
		PlayerData.Release(player)
		Telemetry.Add("PlayerLeft")
	end)
end

return PlayerData
