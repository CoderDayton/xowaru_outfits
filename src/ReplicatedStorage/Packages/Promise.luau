--[[
    Promise.lua
    A simple Promise implementation for asynchronous operations in Roblox Lua.
    Inspired by JavaScript Promises.
]]

local Promise = {}
Promise.__index = Promise

local PENDING = 0
local FULFILLED = 1
local REJECTED = 2

--------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------
function Promise.new(executor)
    local self = setmetatable({
        _state = PENDING,
        _value = nil,
        _successHandlers = {},
        _errorHandlers = {},
    }, Promise)

    local function resolve(value)
        if self._state ~= PENDING then
            return
        end
        self._state = FULFILLED
        self._value = value

        -- Run all success handlers immediately
        for _, handler in ipairs(self._successHandlers) do
            handler(value)
        end

        -- Clean up
        self._successHandlers = nil
        self._errorHandlers = nil
    end

    local function reject(reason)
        if self._state ~= PENDING then
            return
        end
        self._state = REJECTED
        self._value = reason

        -- Run all error handlers immediately
        for _, handler in ipairs(self._errorHandlers) do
            handler(reason)
        end

        -- Clean up
        self._successHandlers = nil
        self._errorHandlers = nil
    end

    -- Execute immediately with built-in error catching
    local success, err = pcall(function()
        executor(resolve, reject)
    end)

    if not success then
        reject(err)
    end

    return self
end

--------------------------------------------------------------------
-- Chaining methods
--------------------------------------------------------------------
function Promise:andThen(onSuccess, onError)
    return Promise.new(function(resolve, reject)
        local function handleSuccess(value)
            if type(onSuccess) ~= "function" then
                resolve(value)
                return
            end

            local ok, result = pcall(onSuccess, value)
            return ok and resolve(result) or reject(result)
        end

        local function handleError(reason)
            if type(onError) ~= "function" then
                reject(reason)
                return
            end

            local ok, result = pcall(onError, reason)
            return ok and resolve(result) or reject(result)
        end

        if self._state == PENDING then
            table.insert(self._successHandlers, handleSuccess)
            table.insert(self._errorHandlers, handleError)
        elseif self._state == FULFILLED then
            handleSuccess(self._value)
        else -- REJECTED
            handleError(self._value)
        end
    end)
end

function Promise:catch(onError)
    return self:andThen(nil, onError)
end

--------------------------------------------------------------------
-- Static helpers
--------------------------------------------------------------------
function Promise.resolve(value)
    return Promise.new(function(resolve)
        resolve(value)
    end)
end

function Promise.reject(reason)
    return Promise.new(function(_, reject)
        reject(reason)
    end)
end

function Promise.all(promises)
    assert(type(promises) == "table", "All expects a table of promises")

    return Promise.new(function(resolve, reject)
        local total = #promises
        if total == 0 then
            resolve({})
            return
        end

        local results = {}
        local completed = 0

        for i, promise in ipairs(promises) do
            promise:andThen(function(value)
                results[i] = value
                completed = completed + 1
                if completed == total then
                    resolve(results)
                end
            end, function(reason)
                reject(reason)
            end)
        end
    end)
end

return Promise
