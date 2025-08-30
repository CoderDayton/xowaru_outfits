--!strict
--[[

    Telemetry module for tracking server-side metrics.
]]

local RunService = game:GetService("RunService")
assert(RunService:IsServer(), "Telemetry must be required on the server")

local GameData = require(script.Parent.GameData) -- your base DS wrapper with backoff/budget guard
local Timer = require(script.Parent.Timer) -- your interval/delay helper

export type TelemetryOptions = {
	storeName: string?, -- default: "Telemetry"
	flushEvery: number?, -- seconds; default: 60
	keyPrefix: string?, -- default: "metrics"
	enabled: boolean?, -- default: true
}

local Telemetry = {}
Telemetry.__index = Telemetry

-- Defaults
local STORE_NAME = "Telemetry"
local FLUSH_EVERY = 60 -- seconds
local KEY_PREFIX = "metrics"
local ENABLED = true

-- State
local store = GameData.ForStore(STORE_NAME)
local counters: { [string]: number } = {}
local flushTimer: { Cancel: () -> (), IsActive: () -> boolean }? = nil
local started = false

-- Build per-day, per-server key to spread writes and avoid contention
local function buildKey(): string
	local ymd = os.date("!%Y%m%d") -- UTC day
	return string.format("%s:%s:%s", KEY_PREFIX, ymd, game.JobId)
end

-- Merge function for UpdateAsync (old + new)
local function addInto(old: any, inc: { [string]: number }): { [string]: number }
	local out: { [string]: number } = {}
	if type(old) == "table" then
		for k, v in pairs(old) do
			out[k] = tonumber(v) or 0
		end
	end
	for name, delta in pairs(inc) do
		out[name] = (out[name] or 0) + delta
		if out[name] == 0 then
			out[name] = nil -- optional: drop zeros to keep payload small
		end
	end
	return out
end

local function takeSnapshot(): { [string]: number }
	local snap: { [string]: number } = {}
	for k, v in pairs(counters) do
		snap[k] = v
		counters[k] = nil
	end
	return snap
end

local function flushOnce()
	if not ENABLED then
		return
	end

	-- Nothing to flush?
	local has = next(counters) ~= nil
	if not has then
		return
	end

	local snap = takeSnapshot()
	local key = buildKey()

	-- Use GameData:Update (atomic, backoff + budget-aware under the hood)
	store:Update(key, function(old)
		return addInto(old, snap)
	end)
	-- If UpdateAsync fails after retries, next tick will try again with new increments
end

----------------------------------------------------------------
-- Public API (easy names)
----------------------------------------------------------------

function Telemetry.Setup(opts: TelemetryOptions?)
	if not opts then
		return
	end

	if typeof(opts.storeName) == "string" and opts.storeName ~= "" then
		STORE_NAME = opts.storeName :: string
		store = GameData.ForStore(STORE_NAME)
	end
	if typeof(opts.flushEvery) == "number" and (opts.flushEvery :: number) > 0 then
		FLUSH_EVERY = opts.flushEvery :: number
		if flushTimer and flushTimer.IsActive() then
			flushTimer.Cancel()
			flushTimer = Timer.Every(FLUSH_EVERY, flushOnce)
		end
	end
	if typeof(opts.keyPrefix) == "string" and opts.keyPrefix ~= "" then
		KEY_PREFIX = opts.keyPrefix :: string
	end
	if typeof(opts.enabled) == "boolean" then
		ENABLED = opts.enabled :: boolean
	end
end

-- Add X to a named counter (default 1)
function Telemetry.Add(name: string, amount: number?)
	if not ENABLED then
		return
	end
	local inc = amount ~= nil and amount or 1
	counters[name] = (counters[name] or 0) + inc
end

-- Record a one-off event (same as Add(name, 1))
function Telemetry.Hit(name: string)
	if not ENABLED then
		return
	end
	counters[name] = (counters[name] or 0) + 1
end

-- Record a gauge (last value wins); stored under "gauge:<name>"
function Telemetry.SetGauge(name: string, value: number)
	if not ENABLED then
		return
	end
	counters["gauge:" .. name] = value
end

-- Force a flush now (use sparingly)
function Telemetry.FlushNow()
	flushOnce()
end

-- Start periodic flushing (call once on server init)
function Telemetry.Start()
	if started then
		return
	end
	started = true
	flushTimer = Timer.Every(FLUSH_EVERY, flushOnce)
end

-- Stop periodic flushing
function Telemetry.Stop()
	if flushTimer and flushTimer.IsActive() then
		flushTimer.Cancel()
	end
	flushTimer = nil
	started = false
end

return Telemetry
