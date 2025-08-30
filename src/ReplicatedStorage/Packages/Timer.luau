--!strict
-- Timer.lua
-- Simple timers for delays, intervals, and countdowns.
-- Uses task.spawn/task.wait under the hood, not deprecated wait().

export type TimerHandle = {
	Cancel: () -> (),
	IsActive: () -> boolean,
}

local Timer = {}

-- Delay: run once after `seconds`
function Timer.After(seconds: number, callback: () -> ()): TimerHandle
	assert(type(seconds) == "number" and seconds >= 0, "seconds must be >= 0")
	assert(type(callback) == "function", "callback must be a function")

	local cancelled = false

	local handle: TimerHandle = {
		Cancel = function()
			cancelled = true
		end,
		IsActive = function()
			return not cancelled
		end,
	}

	task.spawn(function()
		task.wait(seconds)
		if not cancelled then
			callback()
		end
	end)

	return handle
end

-- Interval: run repeatedly every `seconds` until Cancel()
function Timer.Every(seconds: number, callback: () -> ()): TimerHandle
	assert(type(seconds) == "number" and seconds > 0, "seconds must be > 0")
	assert(type(callback) == "function", "callback must be a function")

	local cancelled = false

	local handle: TimerHandle = {
		Cancel = function()
			cancelled = true
		end,
		IsActive = function()
			return not cancelled
		end,
	}

	task.spawn(function()
		while not cancelled do
			task.wait(seconds)
			if cancelled then
				break
			end
			callback()
		end
	end)

	return handle
end

-- Countdown: call onTick each second with remaining time; then call onDone
function Timer.Countdown(totalSeconds: number, onTick: (remaining: number) -> (), onDone: () -> ()): TimerHandle
	assert(type(totalSeconds) == "number" and totalSeconds >= 0, "totalSeconds must be >= 0")
	assert(type(onTick) == "function", "onTick must be a function")
	assert(type(onDone) == "function", "onDone must be a function")

	local cancelled = false

	local handle: TimerHandle = {
		Cancel = function()
			cancelled = true
		end,
		IsActive = function()
			return not cancelled
		end,
	}

	task.spawn(function()
		local remaining = math.floor(totalSeconds)
		while remaining > 0 and not cancelled do
			onTick(remaining)
			task.wait(1)
			remaining -= 1
		end
		if not cancelled then
			onDone()
		end
	end)

	return handle
end

return Timer :: TimerHandle
