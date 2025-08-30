--[[
    Maid.lua
    Purpose: Track tasks (connections, instances, callbacks) and clean them up in one call.
    Fast, GC-friendly, zero external dependencies.

    Example:
        local Maid        = require(game.ReplicatedStorage.Maid)
        local RemoteSignal = require(game.ReplicatedStorage.RemoteSignal)

        local maid = Maid.new()

        -- Listen for a RemoteEvent
        maid += RemoteSignal.OnClient("Damage", function(amount)
            print("You took", amount, "damage")
        end)

        -- Local UI channel
        maid += RemoteSignal.OnLocal("HUD", updateHud)

        -- When the screen closes, clean everything
        script.Parent.CloseButton.MouseButton1Click:Connect(function()
            maid:Clean()
            script.Parent:Destroy()
        end)
]]

local Maid = {}
Maid.__index = Maid

------------------------------------------------------------------
-- CONSTRUCTOR
------------------------------------------------------------------

-- local maid = Maid.new()
function Maid.new()
	-- _tasks is a simple sequential array; avoids hash-table penalties
	return setmetatable({ _tasks = {} }, Maid)
end

------------------------------------------------------------------
-- ADDING WORK
------------------------------------------------------------------

-- maid:Give(task)
-- task may be:
--   • RBXScriptConnection  ➜ Disconnect()
--   • Instance             ➜ Destroy()
--   • function()           ➜ call it
function Maid:Give(task)
	local kind = typeof(task)

	if kind == "RBXScriptConnection" or kind == "Instance" or kind == "function" then
		self._tasks[#self._tasks + 1] = task
	else
		error(("Maid.Give ▸ unsupported type %s"):format(kind))
	end

	return task -- handy for one-liners: maid:Give(part.Touched:Connect(...))
end

-- Syntactic sugar: maid += task
Maid.__add = Maid.Give

------------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------------

-- maid:Clean()  ➜ run/Destroy/Disconnect everything, empty list
function Maid:Clean()
	-- iterate backwards; cheaper when removing from array
	for i = #self._tasks, 1, -1 do
		local task = self._tasks[i]
		local kind = typeof(task)

		if kind == "RBXScriptConnection" then
			task:Disconnect()
		elseif kind == "Instance" then
			if task.Parent then -- minor guard
				task:Destroy()
			end
		else -- function
			task()
		end

		self._tasks[i] = nil
	end
end

------------------------------------------------------------------
-- REMOVE SINGLE TASK (optional)
------------------------------------------------------------------

-- maid:Remove(task) ➜ true if found
function Maid:Remove(task)
	for i, v in ipairs(self._tasks) do
		if v == task then
			table.remove(self._tasks, i)
			return true
		end
	end
	return false
end

------------------------------------------------------------------
-- ALIAS
------------------------------------------------------------------

Maid.DoCleaning = Maid.Clean -- familiarity with Quenty’s API

return Maid
