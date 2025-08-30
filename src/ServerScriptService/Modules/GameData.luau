--!strict
-- GameData.lua
-- Typed, cached DataStore wrapper with backoff/jitter and budget guard

local DataStoreService = game:GetService("DataStoreService")

local Backoff = require(script.Parent.Backoff)
local Promise = require(game.ReplicatedStorage.Packages.Promise)

export type CacheEntry = {
	data: any,
	timestamp: number,
	ttl: number,
}

export type GameDataStore = {
	StoreName: string,
	Get: (self: GameDataStore, key: string, ttl: number?) -> any,
	Set: (self: GameDataStore, key: string, value: any) -> any,
	Update: (self: GameDataStore, key: string, updater: (old: any) -> any) -> any,
	Increment: (self: GameDataStore, key: string, delta: number) -> any,
	Remove: (self: GameDataStore, key: string) -> any,
	GetCached: (self: GameDataStore, key: string) -> any?,
	InvalidateCache: (self: GameDataStore, key: string) -> (),
}

local GameData = {}
GameData.__index = GameData

local DEFAULT_TTL = 300 -- seconds
local cache: { [string]: CacheEntry } = {}
local stores: { [string]: DataStore } = {}

local function getStore(storeName: string): DataStore
	local ds = stores[storeName]
	if not ds then
		ds = DataStoreService:GetDataStore(storeName)
		stores[storeName] = ds
	end
	return ds
end

local function cacheKey(storeName: string, key: string): string
	return storeName .. ":" .. key
end

local function cacheValid(entry: CacheEntry): boolean
	return (os.time() - entry.timestamp) < entry.ttl
end

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	-- Optional guard to avoid immediate throttling when budget is 0
	-- Limit docs: use GetRequestBudgetForRequestType and backoff under pressure. [1]
	while DataStoreService:GetRequestBudgetForRequestType(requestType) <= 0 do
		task.wait(0.05)
	end
end

function GameData.ForStore(storeName: string): GameDataStore
	local self = setmetatable({
		StoreName = storeName,
	}, GameData) :: any
	return (self :: any) :: GameDataStore
end

function GameData:GetCached(key: string): any?
	local ck = cacheKey(self.StoreName, key)
	local entry = cache[ck]
	if entry and cacheValid(entry) then
		return entry.data
	end
	return nil
end

function GameData:InvalidateCache(key: string): ()
	cache[cacheKey(self.StoreName, key)] = nil
end

function GameData:Get(key: string, ttl: number?): any
	local existing = self:GetCached(key)
	if existing ~= nil then
		return Promise.Resolve(existing)
	end

	return Backoff.RetryAsync(function()
		waitForBudget(Enum.DataStoreRequestType.GetAsync) -- respects per-minute budgets. [1]
		local ds = getStore(self.StoreName)
		local value = ds:GetAsync(key)

		cache[cacheKey(self.StoreName, key)] = {
			data = value,
			timestamp = os.time(),
			ttl = ttl or DEFAULT_TTL,
		}
		return value
	end, {
		maxRetries = 5,
		baseDelay = 0.25,
		maxDelay = 6.0,
		jitterFactor = 0.2,
	}) -- exponential backoff with jitter is recommended under throttling. [1]
end

function GameData:Set(key: string, value: any): any
	self:InvalidateCache(key)
	return Backoff.RetryAsync(function()
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync) -- Set/Update share budget. [1]
		local ds = getStore(self.StoreName)
		ds:SetAsync(key, value)
		return value
	end, {
		maxRetries = 5,
		baseDelay = 0.5,
		maxDelay = 8.0,
		jitterFactor = 0.2,
	})
end

function GameData:Update(key: string, updater: (old: any) -> any): any
	self:InvalidateCache(key)
	return Backoff.RetryAsync(function()
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ds = getStore(self.StoreName)
		local newVal = ds:UpdateAsync(key, function(old: any)
			return updater(old)
		end)
		return newVal
	end, {
		maxRetries = 5,
		baseDelay = 0.5,
		maxDelay = 8.0,
		jitterFactor = 0.2,
	}) -- UpdateAsync is preferred for atomic transforms when applicable. [3]
end

function GameData:Increment(key: string, delta: number): any
	self:InvalidateCache(key)
	return Backoff.RetryAsync(function()
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ds = getStore(self.StoreName)
		local newVal = ds:IncrementAsync(key, delta)
		return newVal
	end, {
		maxRetries = 5,
		baseDelay = 0.5,
		maxDelay = 8.0,
		jitterFactor = 0.2,
	})
end

function GameData:Remove(key: string): any
	self:InvalidateCache(key)
	return Backoff.RetryAsync(function()
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ds = getStore(self.StoreName)
		ds:RemoveAsync(key)
		return true
	end, {
		maxRetries = 5,
		baseDelay = 0.5,
		maxDelay = 8.0,
		jitterFactor = 0.2,
	}) -- RemoveAsync has its own throttle/drop codes in 306-class; backoff helps. [1]
end

return GameData :: GameDataStore
