--!strict
--[[
    State.luau
    Typed reactive state management
]]

export type StateValue = string | number | boolean | { any } | nil
export type StateData = { [string]: StateValue }
export type ChangeCallback = (newValue: StateValue, oldValue: StateValue) -> ()
export type Connection = {
	Disconnect: () -> (),
}

local Maid = require(script.Parent.Maid)

local State = {}
State.__index = State

function State.new(initialData: StateData?): State
	local self = setmetatable({
		_data = initialData or {},
		_watchers = {} :: { [string]: { ChangeCallback } },
		_maid = Maid.new(),
	}, State)

	return self
end

function State:Get(key: string): StateValue
	return self._data[key]
end

function State:Set(key: string, value: StateValue): ()
	local oldValue: StateValue = self._data[key]
	if oldValue == value then
		return
	end

	self._data[key] = value

	local watchers: { ChangeCallback }? = self._watchers[key]
	if watchers then
		for _, callback: ChangeCallback in ipairs(watchers) do
			callback(value, oldValue)
		end
	end
end

function State:Update(changes: StateData): ()
	for key: string, value: StateValue in pairs(changes) do
		self:Set(key, value)
	end
end

function State:OnChange(key: string, callback: ChangeCallback): Connection
	if not self._watchers[key] then
		self._watchers[key] = {}
	end

	table.insert(self._watchers[key], callback)

	local connection: Connection = {
		Disconnect = function()
			local watchers: { ChangeCallback }? = self._watchers[key]
			if watchers then
				local index: number? = table.find(watchers, callback)
				if index then
					table.remove(watchers, index)
				end
			end
		end,
	}

	self._maid:Give(connection)
	return connection
end

function State:GetAll(): StateData
	return table.clone(self._data)
end

function State:Destroy(): ()
	self._maid:Clean()
	table.clear(self._watchers)
	table.clear(self._data)
end

export type State = typeof(State.new())

--------------------------------------------------------------------
-- SHOP STATE INSTANCE
--------------------------------------------------------------------

export type ShopStateData = {
	selectedOutfit: string?,
	previewModel: Model?,
	playerRobux: number,
	currentCategory: string,
	searchFilter: string,
	isLoading: boolean,
	ownedAssets: { [string]: boolean },
}

local ShopState: State = State.new({
	selectedOutfit = nil,
	previewModel = nil,
	playerRobux = 0,
	currentCategory = "all",
	searchFilter = "",
	isLoading = false,
	ownedAssets = {},
})

State.Shop = ShopState

return State
