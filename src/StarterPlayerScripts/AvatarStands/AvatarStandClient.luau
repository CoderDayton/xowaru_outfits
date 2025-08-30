--!strict
--[[
	Avatar Stand Client Manager
	Handles client-side interactions, UI, and visual effects for Avatar Stands
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

-- Import modules
local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(ReplicatedStorage.Packages.Signal)
local State = require(ReplicatedStorage.Packages.State)
local Maid = require(ReplicatedStorage.Packages.Maid)

-- Import Avatar Stands modules
local AvatarStandsTypes = require(ReplicatedStorage.AvatarStands.Types)
local AvatarStandsConfig = require(ReplicatedStorage.AvatarStands.Config)

type Promise<T> = typeof(Promise.new(function() end))
type StandConfig = AvatarStandsTypes.StandConfig
type UIState = AvatarStandsTypes.UIState
type ViewMode = AvatarStandsTypes.ViewMode

-- Event names for Signal system
local CLIENT_EVENTS = {
	STAND_DATA_RECEIVED = "StandDataReceived",
	STAND_UPDATED = "StandUpdated",
	INTERACTION_ZONE_ENTERED = "InteractionZoneEntered",
	INTERACTION_ZONE_EXITED = "InteractionZoneExited",
	UI_STATE_CHANGED = "UIStateChanged",
}

local AvatarStandClient = {}
AvatarStandClient.__index = AvatarStandClient

-- State Management
local stands = State.new({} :: {[string]: StandConfig})
local activeStandId = State.new(nil :: string?)
local isEditMode = State.new(false)
local currentView = State.new("Gallery" :: ViewMode)

local uiState = State.computed(function(use)
	return {
		activeStandId = use(activeStandId),
		isEditMode = use(isEditMode),
		isCustomizing = false,
		selectedCategory = nil,
		currentView = use(currentView),
	} :: UIState
end)

-- UI Elements
local screenGui: ScreenGui?
local mainFrame: Frame?
local standInteractionUI: Frame?
local maid = Maid.new()

function AvatarStandClient.new()
	local self = setmetatable({}, AvatarStandClient)

	self:_initializeUI()
	self:_setupStateConnections()
	self:_setupInputHandling()

	return self
end

function AvatarStandClient:getStands(): {[string]: StandConfig}
	return stands:get()
end

function AvatarStandClient:getActiveStand(): StandConfig?
	local activeId = activeStandId:get()
	if activeId then
		return stands:get()[activeId]
	end
	return nil
end

function AvatarStandClient:setActiveStand(standId: string?)
	activeStandId:set(standId)
end

function AvatarStandClient:enterEditMode(standId: string)
	self:setActiveStand(standId)
	isEditMode:set(true)
	currentView:set("Edit")
	self:_showEditUI(standId)
end

function AvatarStandClient:exitEditMode()
	isEditMode:set(false)
	currentView:set("Gallery")
	self:_hideEditUI()
end

function AvatarStandClient:openStandCustomization(standId: string)
	self:setActiveStand(standId)
	currentView:set("Customize")
	self:_showCustomizationUI(standId)
end

function AvatarStandClient:showStandDetails(standId: string)
	self:setActiveStand(standId)
	currentView:set("Detailed")
	self:_showDetailsUI(standId)
end

function AvatarStandClient:onStandInteractionZoneEntered(standId: string)
	Signal.FireAll(CLIENT_EVENTS.INTERACTION_ZONE_ENTERED, standId)
	self:_showInteractionPrompt(standId)
end

function AvatarStandClient:onStandInteractionZoneExited(standId: string)
	Signal.FireAll(CLIENT_EVENTS.INTERACTION_ZONE_EXITED, standId)
	self:_hideInteractionPrompt()
end

-- Private Methods

function AvatarStandClient:_initializeUI()
	-- Create main ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AvatarStandsUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Main container frame
	mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromScale(1, 1)
	mainFrame.Position = UDim2.new(0, 0, 0, 0)
	mainFrame.BackgroundTransparency = 1
	mainFrame.Parent = screenGui

	-- Stand Interaction UI (proximity-based)
	standInteractionUI = self:_createInteractionUI()
	standInteractionUI.Parent = mainFrame

	-- Wait for PlayerGui to be ready
	LocalPlayer:WaitForChild("PlayerGui")
	screenGui.Parent = LocalPlayer.PlayerGui

	maid:GiveTask(screenGui)
end

function AvatarStandClient:_createInteractionUI(): Frame
	local interactionFrame = Instance.new("Frame")
	interactionFrame.Name = "StandInteractionFrame"
	interactionFrame.Size = UDim2.fromOffset(300, 150)
	interactionFrame.Position = UDim2.new(0.5, -150, 0.8, -75)
	interactionFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	interactionFrame.BackgroundTransparency = 0.1
	interactionFrame.BorderSizePixel = 0
	interactionFrame.Visible = false

	-- Add corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, AvatarStandsConfig.UI_CONFIG.panelCornerRadius)
	corner.Parent = interactionFrame

	-- Add drop shadow
	local shadow = Instance.new("ImageLabel")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(1, 20, 1, 20)
	shadow.Position = UDim2.fromOffset(-10, -10)
	shadow.BackgroundTransparency = 1
	shadow.Image = "rbxasset://textures/ui/Controls/DropShadow.png"
	shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
	shadow.ImageTransparency = 0.5
	shadow.ScaleType = Enum.ScaleType.Slice
	shadow.SliceCenter = Rect.new(12, 12, 52, 52)
	shadow.ZIndex = interactionFrame.ZIndex - 1
	shadow.Parent = interactionFrame

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 30)
	title.Position = UDim2.fromOffset(10, 10)
	title.BackgroundTransparency = 1
	title.Text = "Avatar Stand"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.Parent = interactionFrame

	-- Buttons container
	local buttonsFrame = Instance.new("Frame")
	buttonsFrame.Name = "ButtonsFrame"
	buttonsFrame.Size = UDim2.new(1, -20, 0, 80)
	buttonsFrame.Position = UDim2.fromOffset(10, 50)
	buttonsFrame.BackgroundTransparency = 1
	buttonsFrame.Parent = interactionFrame

	-- Button layout
	local buttonLayout = Instance.new("UIGridLayout")
	buttonLayout.CellSize = UDim2.fromScale(0.45, 0.45)
	buttonLayout.CellPadding = UDim2.fromScale(0.05, 0.05)
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	buttonLayout.Parent = buttonsFrame

	-- Create interaction buttons
	local buttons = {
		{text = "View", action = "view"},
		{text = "Edit", action = "edit"},
		{text = "Customize", action = "customize"},
		{text = "Close", action = "close"},
	}

	for _, buttonData in buttons do
		local button = self:_createButton(buttonData.text, buttonData.action)
		button.Parent = buttonsFrame
	end

	return interactionFrame
end

function AvatarStandClient:_createButton(text: string, action: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = text .. "Button"
	button.Text = text
	button.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Font = Enum.Font.Gotham

	-- Add corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = button

	-- Hover effects
	local defaultTween = AvatarStandsConfig.UI_CONFIG.defaultTweenInfo

	button.MouseEnter:Connect(function()
		local hoverTween = TweenService:Create(
			button,
			defaultTween,
			{
				BackgroundColor3 = Color3.fromRGB(70, 70, 70),
				Size = button.Size * AvatarStandsConfig.UI_CONFIG.buttonHoverScale
			}
		)
		hoverTween:Play()
	end)

	button.MouseLeave:Connect(function()
		local leaveTween = TweenService:Create(
			button,
			defaultTween,
			{
				BackgroundColor3 = Color3.fromRGB(50, 50, 50),
				Size = button.Size / AvatarStandsConfig.UI_CONFIG.buttonHoverScale
			}
		)
		leaveTween:Play()
	end)

	-- Button actions
	button.Activated:Connect(function()
		self:_handleButtonAction(action)
	end)

	return button
end

function AvatarStandClient:_handleButtonAction(action: string)
	local activeId = activeStandId:get()

	if action == "view" and activeId then
		self:showStandDetails(activeId)
	elseif action == "edit" and activeId then
		self:enterEditMode(activeId)
	elseif action == "customize" and activeId then
		self:openStandCustomization(activeId)
	elseif action == "close" then
		self:_hideInteractionPrompt()
	end
end

function AvatarStandClient:_showInteractionPrompt(standId: string)
	if not standInteractionUI then return end

	self:setActiveStand(standId)

	-- Update title with stand info
	local standConfig = stands:get()[standId]
	if standConfig then
		local title = standInteractionUI:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Text = "Avatar Stand - " .. (standConfig.standType or "Basic")
		end
	end

	-- Animate in
	standInteractionUI.Visible = true
	standInteractionUI.Position = UDim2.new(0.5, -150, 1, 0)

	local slideInTween = TweenService:Create(
		standInteractionUI,
		TweenInfo.new(
			AvatarStandsConfig.UI_CONFIG.fadeInDuration,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		),
		{Position = UDim2.new(0.5, -150, 0.8, -75)}
	)
	slideInTween:Play()
end

function AvatarStandClient:_hideInteractionPrompt()
	if not standInteractionUI or not standInteractionUI.Visible then return end

	local slideOutTween = TweenService:Create(
		standInteractionUI,
		TweenInfo.new(
			AvatarStandsConfig.UI_CONFIG.fadeOutDuration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		),
		{Position = UDim2.new(0.5, -150, 1, 0)}
	)

	slideOutTween:Play()
	slideOutTween.Completed:Connect(function()
		standInteractionUI.Visible = false
	end)
end

function AvatarStandClient:_showEditUI(standId: string)
	-- Placeholder for edit UI
	print("Showing edit UI for stand:", standId)
end

function AvatarStandClient:_hideEditUI()
	-- Placeholder for hiding edit UI
	print("Hiding edit UI")
end

function AvatarStandClient:_showCustomizationUI(standId: string)
	-- Placeholder for customization UI
	print("Showing customization UI for stand:", standId)
end

function AvatarStandClient:_showDetailsUI(standId: string)
	-- Placeholder for details UI
	print("Showing details UI for stand:", standId)
end

function AvatarStandClient:_setupStateConnections()
	-- React to UI state changes
	uiState:onChange(function(newState)
		Signal.FireAll(CLIENT_EVENTS.UI_STATE_CHANGED, newState)
	end)

	-- React to stands data changes
	stands:onChange(function(newStands)
		Signal.FireAll(CLIENT_EVENTS.STAND_DATA_RECEIVED, newStands)
	end)
end

function AvatarStandClient:_setupInputHandling()
	-- Handle escape key to close UIs
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.Escape then
			if isEditMode:get() then
				self:exitEditMode()
			elseif standInteractionUI and standInteractionUI.Visible then
				self:_hideInteractionPrompt()
			end
		end
	end)
end

-- Export module state for external use
AvatarStandClient.State = {
	stands = stands,
	activeStandId = activeStandId,
	isEditMode = isEditMode,
	currentView = currentView,
	uiState = uiState,
}

return AvatarStandClient
