--[[
    Signal.lua
    All-in-one wrapper: RemoteEvent + BindableEvent + Maid cleanup

    Example:
        local Signal = require(ReplicatedStorage.Utils.Signal)

        -- listen
        Signal.OnLocal("HUD", function(state)
            print("HUD state changed", state)
        end)

        -- fire (anywhere on the same client)
        Signal.FireLocal("HUD", {health = 95})
        Client ⇄ Server chat

        lua
        -- LocalScript
        Signal.OnClient("Chat", function(from, msg)
            print(from .. ":", msg)
        end)

        Signal.FireServer("Chat", "Hello!")

        -- Script (server)
        Signal.OnServer("Chat", function(player, msg)
            Signal.FireAll("Chat", player.Name, msg)
        end)
        Cleanup when the feature ends

        lua
        Signal.Cleanup("Chat")   -- removes all Chat listeners & connections
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Maid = require(script.Parent.Maid)

--------------------------------------------------------------------
-- INTERNAL CACHES
--------------------------------------------------------------------

local remotes = {} -- name ➜ RemoteEvent
local bindables = {} -- name ➜ BindableEvent  (client only)
local serverBindables = {} -- name ➜ BindableEvent (server only)
local maids = {} -- name ➜ Maid           (handles cleanup)

--------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------

local function getMaid(name)
	if not maids[name] then
		maids[name] = Maid.new()
	end
	return maids[name]
end

local function getRemote(name)
	local remote = remotes[name]
	if not remote then
		remote = ReplicatedStorage:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = ReplicatedStorage
		end
		remotes[name] = remote
	end
	return remote
end

local function getBindable(name)
	assert(RunService:IsClient(), "Bindable events exist only on the client")
	local bindable = bindables[name]
	if not bindable then
		bindable = Instance.new("BindableEvent")
		bindable.Name = "BE_" .. name
		bindables[name] = bindable
	end
	return bindable
end

local function getServerBindable(name)
	assert(RunService:IsServer(), "Server bindables are server-only")
	local bindable = serverBindables[name]
	if not bindable then
		bindable = Instance.new("BindableEvent")
		bindable.Name = "BE_" .. name
		serverBindables[name] = bindable
	end
	return bindable
end

--------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------

local RemoteSignal = {}

------------------------------------------------------------------
-- 🔊  LISTEN
------------------------------------------------------------------

-- Client listens to server-sent RemoteEvent
function RemoteSignal.OnClient(eventName, fn)
	assert(RunService:IsClient(), "OnClient only in LocalScript")
	local r = getRemote(eventName)
	local m = getMaid(eventName)
	local c = r.OnClientEvent:Connect(fn)
	m:GiveTask(c)
	return c
end

-- Server listens to client-sent RemoteEvent
function RemoteSignal.OnServer(eventName, fn)
	assert(RunService:IsServer(), "OnServer only in Script")
	local r = getRemote(eventName)
	local m = getMaid(eventName)
	local c = r.OnServerEvent:Connect(fn)
	m:GiveTask(c)
	return c
end

-- Client-local BindableEvent listener (zero-lag UI updates)
function RemoteSignal.OnLocal(eventName, fn)
	assert(RunService:IsClient(), "OnLocal only in LocalScript")
	local b = getBindable(eventName)
	local m = getMaid(eventName .. "_local")
	local c = b.Event:Connect(fn)
	m:GiveTask(c)
	return c
end

-- Server-Server BindableEvent listener (zero-lag internal events)
function RemoteSignal.OnServerLocal(eventName, fn)
	assert(RunService:IsServer(), "OnServerLocal only in Script (server)")
	local b = getServerBindable(eventName)
	local m = getMaid(eventName .. "_server")
	local c = b.Event:Connect(fn)
	m:GiveTask(c)
	return c
end

------------------------------------------------------------------
-- 🚀  FIRE
------------------------------------------------------------------

-- Client ➜ Server
function RemoteSignal.FireServer(eventName, ...)
	assert(RunService:IsClient(), "FireServer only in LocalScript")
	getRemote(eventName):FireServer(...)
end

-- Server ➜ Client (one)
function RemoteSignal.FireClient(eventName, player, ...)
	assert(RunService:IsServer(), "FireClient only in Script")
	getRemote(eventName):FireClient(player, ...)
end

-- Server ➜ Client (all)
function RemoteSignal.FireAll(eventName, ...)
	assert(RunService:IsServer(), "FireAll only in Script")
	getRemote(eventName):FireAllClients(...)
end

-- Client ➜ Client (same device)
function RemoteSignal.FireLocal(eventName, ...)
	assert(RunService:IsClient(), "FireLocal only in LocalScript")
	getBindable(eventName):Fire(...)
end

-- Server ➜ Server (same server)
function RemoteSignal.FireServerLocal(eventName, ...)
	assert(RunService:IsServer(), "FireServerLocal only in Script (server)")
	getServerBindable(eventName):Fire(...)
end

------------------------------------------------------------------
-- 🧹  CLEANUP
------------------------------------------------------------------

function RemoteSignal.Cleanup(eventName)
	if maids[eventName] then
		maids[eventName]:DoCleaning()
		maids[eventName] = nil
	end
end

function RemoteSignal.CleanupAll()
	for _, m in pairs(maids) do
		m:DoCleaning()
	end
	table.clear(maids)
end

return RemoteSignal
