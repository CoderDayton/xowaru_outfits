--!strict
-- Backoff.lua
-- Exponential backoff with jitter for DataStore retry logic
-- Prevents thundering herd, handles rate limiting gracefully

local Backoff = {}

export type BackoffConfig = {
	maxRetries: number?,
	baseDelay: number?,
	maxDelay: number?,
	jitterFactor: number?,
	exponentialBase: number?,
}

export type RetryFunction<T> = () -> T

local DEFAULT_CONFIG: BackoffConfig = {
	maxRetries = 5,
	baseDelay = 0.1,
	maxDelay = 10.0,
	jitterFactor = 0.1,
	exponentialBase = 2.0,
}

local function applyJitter(delay: number, jitterFactor: number): number
	local jitter: number = delay * jitterFactor * (math.random() * 2 - 1)
	return math.max(0.05, delay + jitter)
end

function Backoff.Retry<T>(fn: RetryFunction<T>, config: BackoffConfig?): T?
	local cfg: BackoffConfig = config or DEFAULT_CONFIG

	local maxRetries: number = cfg.maxRetries or DEFAULT_CONFIG.maxRetries
	local baseDelay: number = cfg.baseDelay or DEFAULT_CONFIG.baseDelay
	local maxDelay: number = cfg.maxDelay or DEFAULT_CONFIG.maxDelay
	local jitterFactor: number = cfg.jitterFactor or DEFAULT_CONFIG.jitterFactor
	local exponentialBase: number = cfg.exponentialBase or DEFAULT_CONFIG.exponentialBase

	local attempt: number = 0
	local delay: number = baseDelay

	while attempt <= maxRetries do
		local success: boolean, result: any = pcall(fn)

		if success then
			return result
		end

		attempt += 1

		if attempt <= maxRetries then
			local actualDelay: number = math.min(delay, maxDelay)
			actualDelay = applyJitter(actualDelay, jitterFactor)

			task.wait(actualDelay)
			delay *= exponentialBase
		end
	end

	return nil
end

-- Promise-based version
function Backoff.RetryAsync<T>(fn: RetryFunction<T>, config: BackoffConfig?): any
	local Promise = require(game.ReplicatedStorage.Packages.Promise)

	return Promise.new(function(resolve, reject)
		local result: T? = Backoff.Retry(fn, config)
		if result ~= nil then
			resolve(result)
		else
			reject("Max retries exceeded")
		end
	end)
end

return Backoff
