--[[
    SoundHandler.luau
    This module provides functionality to preload sounds, play sounds with specific configurations,
    and manage sound channels for efficient playback.
]]

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local SoundHandler = {}

-- Sound pooling for frequently used sounds
local soundPools: { [string]: { Sound } } = {}
local POOL_SIZE = 3 -- Max pooled instances per sound

-- Volume control for different sound categories
local volumeMultipliers = {
	ui_clicks = 1.0,
	ui_menu = 1.0,
	ui_feedback = 1.0,
	master = 1.0,
}

-- Configure logical sounds
local soundConfigs = {
	ButtonSound = { id = "rbxassetid://107852734860621", volume = 0.2, playbackSpeed = 0.5 },
	ClickSound = { id = "rbxassetid://1673280232", volume = 0.03, playbackSpeed = 1.0 },
	MenuOpen = { id = "rbxassetid://110059957735733", volume = 0.2, playbackSpeed = 1.0 },
	MenuClose = { id = "rbxassetid://97861038165143", volume = 0.2, playbackSpeed = 1.0 },
	PositiveFeedback = { id = "rbxassetid://77117485112690", volume = 0.1, playbackSpeed = 1.0 },
}

-- Map sounds to logical channels for polyphony control
local soundChannels = {
	ButtonSound = "ui_clicks",
	ClickSound = "ui_clicks",
	MenuOpen = "ui_menu",
	MenuClose = "ui_menu",
	PositiveFeedback = "ui_feedback",
}

-- Max overlapping instances per channel
local channelLimits = {
	ui_clicks = 4, -- allow rapid click overlaps
	ui_menu = 1, -- single-voice; new replaces old
	ui_feedback = 2,
}

local preloadedSounds: { [string]: Sound } = {}
local activeByChannel: { [string]: { Sound } } = {}

local FADE_TIME = 0.08 -- short linear fade to prevent pops

-- Get a sound from the pool or create new one
local function getFromPool(name: string): Sound?
	local pool = soundPools[name]
	if pool and #pool > 0 then
		return table.remove(pool)
	end
	return nil
end

-- Return a sound to the pool for reuse
local function returnToPool(name: string, sound: Sound)
	if not soundPools[name] then
		soundPools[name] = {}
	end
	local pool = soundPools[name]
	if #pool < POOL_SIZE then
		sound:Stop()
		sound.Parent = nil
		table.insert(pool, sound)
	else
		sound:Destroy()
	end
end

-- Fade to near-zero and destroy
local function fadeAndDestroy(s: Sound)
	if not s or not s.Parent then
		return
	end
	if s:GetAttribute("FadingOut") then
		return
	end
	s:SetAttribute("FadingOut", true)
	local tween = TweenService:Create(s, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Linear), { Volume = 0.0001 })
	tween:Play()
	tween.Completed:Once(function()
		if s.IsPlaying then
			pcall(function()
				s:Stop()
			end)
		end
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- Remove a sound from channel tracking
local function removeActive(channel: string, snd: Sound)
	local list = activeByChannel[channel]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i] == snd then
			table.remove(list, i)
			break
		end
	end
end

-- Push a sound to a channel with limit enforcement
local function pushActive(channel: string, snd: Sound)
	local list = activeByChannel[channel]
	if not list then
		list = {}
		activeByChannel[channel] = list
	end
	table.insert(list, snd)
	local limit = channelLimits[channel] or 1
	while #list > limit do
		local victim = table.remove(list, 1)
		fadeAndDestroy(victim)
	end
end

-- Begin replacement for an existing instance (used for single-voice channels)
local function beginReplacement(oldSound: Sound?)
	if not oldSound then
		return
	end
	-- Remove from whichever channel it resides in
	for ch, arr in pairs(activeByChannel) do
		for i = #arr, 1, -1 do
			if arr[i] == oldSound then
				table.remove(arr, i)
				break
			end
		end
	end
	if oldSound.IsPlaying then
		fadeAndDestroy(oldSound)
	else
		if oldSound.Parent then
			oldSound:Destroy()
		end
	end
end

-- Public: Preload all configured sounds to eliminate first-play hitch
function SoundHandler.Preload()
	if next(preloadedSounds) ~= nil then
		return
	end
	local cacheFolder = Instance.new("Folder")
	cacheFolder.Name = "SoundHandlerCache"
	cacheFolder.Parent = SoundService

	local assets = {}
	for name, cfg in pairs(soundConfigs) do
		local s = Instance.new("Sound")
		s.Name = name .. "_Base"
		s.SoundId = cfg.id
		s.Volume = cfg.volume
		s.PlaybackSpeed = cfg.playbackSpeed
		s.RollOffMode = Enum.RollOffMode.Linear
		s.Parent = cacheFolder
		preloadedSounds[name] = s
		table.insert(assets, s)
	end

	-- Best-effort preload; ignore errors
	pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)
end

-- Set channel volume multiplier
function SoundHandler.SetChannelVolume(channel: string, multiplier: number)
	volumeMultipliers[channel] = math.clamp(multiplier, 0, 1)
end

-- Set master volume multiplier
function SoundHandler.SetMasterVolume(multiplier: number)
	volumeMultipliers.master = math.clamp(multiplier, 0, 1)
end

-- Optional: stop all sounds in a channel (e.g., closing menus)
function SoundHandler.StopChannel(channel: string, fade: number?)
	local list = activeByChannel[channel]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		local snd = list[i]
		if snd then
			if fade and fade > 0 then
				local tween =
					TweenService:Create(snd, TweenInfo.new(fade, Enum.EasingStyle.Linear), { Volume = 0.0001 })
				tween:Play()
				tween.Completed:Once(function()
					if snd.Parent then
						snd:Destroy()
					end
				end)
			else
				if snd.Parent then
					snd:Destroy()
				end
			end
		end
		table.remove(list, i)
	end
end

-- Public: play by logical name with optional overrides
function SoundHandler.PlaySound(name: string, overrideVolume: number?, overridePlaybackSpeed: number?)
	local cfg = soundConfigs[name]
	if not cfg then
		warn("[SoundHandler] Unknown sound:", name)
		return
	end

	-- Resolve channel and enforce single-voice behavior if needed
	local channel = soundChannels[name] or name
	if (channelLimits[channel] or 1) == 1 then
		local list = activeByChannel[channel]
		if list then
			for i = #list, 1, -1 do
				beginReplacement(list[i])
				table.remove(list, i)
			end
		end
	end

	-- Try to get from pool first
	local sound: Sound? = getFromPool(name)
	
	if not sound then
		local base = preloadedSounds[name]
		if base then
			sound = base:Clone()
		else
			-- Fallback if Preload not called
			sound = Instance.new("Sound")
			sound.SoundId = cfg.id
			sound.RollOffMode = Enum.RollOffMode.Linear
		end
	end

	-- Always reset properties (pooled sounds may have modified values)
	sound.Name = name .. "_Play"
	
	-- Apply volume multipliers
	local baseVolume = overrideVolume or cfg.volume
	local channelMult = volumeMultipliers[channel] or 1.0
	local masterMult = volumeMultipliers.master or 1.0
	sound.Volume = baseVolume * channelMult * masterMult
	
	sound.PlaybackSpeed = overridePlaybackSpeed or cfg.playbackSpeed

	-- Centralize under SoundService for consistency
	sound.Parent = SoundService

	-- Track active and finalize cleanly
	pushActive(channel, sound)

	local finalized = false
	local function finalize()
		if finalized then
			return
		end
		finalized = true
		removeActive(channel, sound)
		if sound.Parent then
			returnToPool(name, sound) -- Return to pool instead of destroy
		end
	end

	sound.Ended:Once(finalize)
	sound.Stopped:Once(finalize)

	sound:Play()

	-- Safety timeout in case Ended doesn't fire (e.g., abrupt Parent removal)
	local tl = sound.TimeLength
	if tl <= 0 then
		tl = 3
	end
	local lifetime = (tl / math.max(0.01, sound.PlaybackSpeed)) + 0.25
	task.delay(lifetime, function()
		if sound and sound.Parent then
			finalize()
		end
	end)
end

-- Remove the auto-preload call - should be called explicitly from main code
-- SoundHandler.Preload()

return SoundHandler
