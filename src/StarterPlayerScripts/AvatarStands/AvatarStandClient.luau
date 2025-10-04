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
local RemoteIds = require(ReplicatedStorage.Net.RemoteIds)

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

-- State Management - Single state object with typed keys
local appState = State.new({
	stands = {} :: {[string]: StandConfig},
	activeStandId = nil :: string?,
	isEditMode = false,
	currentView = "Gallery" :: ViewMode,
	hasCreationPermissions = false,
	isCustomizing = false,
	selectedCategory = nil :: string?,
})

-- Combined UI state getter function
local function getUIState(): UIState
	return {
		activeStandId = appState:Get("activeStandId") :: string?,
		isEditMode = appState:Get("isEditMode") :: boolean,
		isCustomizing = appState:Get("isCustomizing") :: boolean,
		selectedCategory = appState:Get("selectedCategory") :: string?,
		currentView = appState:Get("currentView") :: ViewMode,
	}
end

-- Helper functions to access state values
local function getStands(): {[string]: StandConfig}
	return appState:Get("stands") :: {[string]: StandConfig} or {}
end

local function getActiveStandId(): string?
	return appState:Get("activeStandId") :: string?
end

local function isInEditMode(): boolean
	return appState:Get("isEditMode") :: boolean
end

local function getCurrentView(): ViewMode
	return appState:Get("currentView") :: ViewMode
end

local function hasCreationPerms(): boolean
	return appState:Get("hasCreationPermissions") :: boolean
end

-- UI Elements
local screenGui: ScreenGui?
local mainFrame: Frame?
local standInteractionUI: Frame?
local createStandButton: TextButton?
local maid = Maid.new()

function AvatarStandClient.new()
	local self = setmetatable({}, AvatarStandClient)

	self:_initializeUI()
	self:_setupStateConnections()
	self:_setupInputHandling()
	self:_setupNetworking()

	return self
end

function AvatarStandClient:getStands(): {[string]: StandConfig}
	return getStands()
end

function AvatarStandClient:getActiveStand(): StandConfig?
	local activeId = getActiveStandId()
	if activeId then
		local currentStands = getStands()
		return currentStands[activeId]
	end
	return nil
end

function AvatarStandClient:setActiveStand(standId: string?)
	appState:Set("activeStandId", standId)
end

function AvatarStandClient:enterEditMode(standId: string)
	self:setActiveStand(standId)
	appState:Set("isEditMode", true)
	appState:Set("currentView", "Edit")
	self:_showEditUI(standId)
end

function AvatarStandClient:exitEditMode()
	appState:Set("isEditMode", false)
	appState:Set("currentView", "Gallery")
	self:_hideEditUI()
end

function AvatarStandClient:openStandCustomization(standId: string)
	self:setActiveStand(standId)
	appState:Set("currentView", "Customize")
	self:_showCustomizationUI(standId)
end

function AvatarStandClient:showStandDetails(standId: string)
	self:setActiveStand(standId)
	appState:Set("currentView", "Detailed")
	self:_showDetailsUI(standId)
end

function AvatarStandClient:onStandInteractionZoneEntered(standId: string)
	Signal.FireLocal(CLIENT_EVENTS.INTERACTION_ZONE_ENTERED, standId)
	self:_showInteractionPrompt(standId)
end

function AvatarStandClient:onStandInteractionZoneExited(standId: string)
	Signal.FireLocal(CLIENT_EVENTS.INTERACTION_ZONE_EXITED, standId)
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

	maid:Give(screenGui)
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

function AvatarStandClient:_createEditFrame(standId: string): Frame
	local standConfig = getStands()[standId]
	if not standConfig then
		warn(`Cannot create edit frame for unknown stand: {standId}`)
		return Instance.new("Frame")
	end

	local editFrame = Instance.new("Frame")
	editFrame.Name = "EditFrame"
	editFrame.Size = UDim2.fromOffset(400, 400)
	editFrame.Position = UDim2.new(0.5, -200, 0.5, -200)
	editFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	editFrame.BackgroundTransparency = 0.1
	editFrame.BorderSizePixel = 0

	-- Add corner radius and shadow
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, AvatarStandsConfig.UI_CONFIG.panelCornerRadius)
	corner.Parent = editFrame

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 50)
	titleBar.Position = UDim2.new(0, 0, 0, 0)
	titleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	titleBar.BorderSizePixel = 0
	titleBar.Parent = editFrame

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, AvatarStandsConfig.UI_CONFIG.panelCornerRadius)
	titleCorner.Parent = titleBar

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.new(0, 15, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = `Edit Stand - {standConfig.standType or "Basic"}`
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titleBar

	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromOffset(30, 30)
	closeButton.Position = UDim2.new(1, -40, 0.5, -15)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeButton.BorderSizePixel = 0
	closeButton.Text = "×"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextScaled = true
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = titleBar

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 4)
	closeCorner.Parent = closeButton

	closeButton.Activated:Connect(function()
		self:exitEditMode()
	end)

	-- Content area
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ContentScroll"
	scrollFrame.Size = UDim2.new(1, -20, 1, -70)
	scrollFrame.Position = UDim2.new(0, 10, 0, 60)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	scrollFrame.Parent = editFrame

	-- Position controls
	local positionSection = self:_createEditSection(scrollFrame, "Position", 0)
	local xInput = self:_createNumberInput(positionSection, "X:", standConfig.position.X)
	local yInput = self:_createNumberInput(positionSection, "Y:", standConfig.position.Y)
	local zInput = self:_createNumberInput(positionSection, "Z:", standConfig.position.Z)

	-- Rotation controls
	local rotationSection = self:_createEditSection(scrollFrame, "Rotation", 120)
	local rotInput = self:_createNumberInput(rotationSection, "Y Rotation:", math.deg(standConfig.rotation.Y))

	-- Stand type selection
	local typeSection = self:_createEditSection(scrollFrame, "Stand Type", 240)
	local typeDropdown = self:_createDropdown(typeSection, "Type:", standConfig.standType, {"Basic", "Premium", "Animated", "Interactive"})

	-- Save button
	local saveButton = Instance.new("TextButton")
	saveButton.Name = "SaveButton"
	saveButton.Size = UDim2.new(0.8, 0, 0, 40)
	saveButton.Position = UDim2.new(0.1, 0, 1, -50)
	saveButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
	saveButton.BorderSizePixel = 0
	saveButton.Text = "Save Changes"
	saveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	saveButton.TextScaled = true
	saveButton.Font = Enum.Font.GothamBold
	saveButton.Parent = editFrame

	local saveCorner = Instance.new("UICorner")
	saveCorner.CornerRadius = UDim.new(0, 6)
	saveCorner.Parent = saveButton

	saveButton.Activated:Connect(function()
		-- Collect form data and update stand
		local newConfig: StandConfig = {
			standId = standConfig.standId,
			ownerId = standConfig.ownerId,
			position = Vector3.new(tonumber(xInput.Text) or standConfig.position.X, tonumber(yInput.Text) or standConfig.position.Y, tonumber(zInput.Text) or standConfig.position.Z),
			rotation = Vector3.new(0, math.rad(tonumber(rotInput.Text) or math.deg(standConfig.rotation.Y)), 0),
			standType = typeDropdown.Text,
			avatarData = standConfig.avatarData,
			createdAt = standConfig.createdAt,
			lastModified = DateTime.now().UnixTimestamp,
		}

		self:updateStandConfig(standId, newConfig)
		self:exitEditMode()
	end)

	-- Auto-size scroll content
	scrollFrame.CanvasSize = UDim2.fromOffset(0, 320)

	return editFrame
end

function AvatarStandClient:_createCustomizeFrame(standId: string): Frame
	local standConfig = getStands()[standId]
	if not standConfig then
		warn(`Cannot create customize frame for unknown stand: {standId}`)
		return Instance.new("Frame")
	end

	local customizeFrame = Instance.new("Frame")
	customizeFrame.Name = "CustomizeFrame"
	customizeFrame.Size = UDim2.fromOffset(500, 500)
	customizeFrame.Position = UDim2.new(0.5, -250, 0.5, -250)
	customizeFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	customizeFrame.BackgroundTransparency = 0.1
	customizeFrame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, AvatarStandsConfig.UI_CONFIG.panelCornerRadius)
	corner.Parent = customizeFrame

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 50)
	titleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	titleBar.BorderSizePixel = 0
	titleBar.Parent = customizeFrame

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, AvatarStandsConfig.UI_CONFIG.panelCornerRadius)
	titleCorner.Parent = titleBar

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.new(0, 15, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "Customize Avatar"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titleBar

	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(30, 30)
	closeButton.Position = UDim2.new(1, -40, 0.5, -15)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeButton.BorderSizePixel = 0
	closeButton.Text = "×"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextScaled = true
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = titleBar

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 4)
	closeCorner.Parent = closeButton

	closeButton.Activated:Connect(function()
		customizeFrame:Destroy()
		appState:Set("currentView", "Gallery")
	end)

	-- Category tabs
	local tabFrame = Instance.new("Frame")
	tabFrame.Name = "TabFrame"
	tabFrame.Size = UDim2.new(1, -20, 0, 40)
	tabFrame.Position = UDim2.new(0, 10, 0, 60)
	tabFrame.BackgroundTransparency = 1
	tabFrame.Parent = customizeFrame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tabLayout.Padding = UDim.new(0, 5)
	tabLayout.Parent = tabFrame

	local categories = {"Shirts", "Pants", "Accessories", "Hair", "Face", "Body Colors"}
	local tabs = {}

	for i, category in categories do
		local tab = Instance.new("TextButton")
		tab.Name = category .. "Tab"
		tab.Size = UDim2.fromOffset(80, 35)
		tab.BackgroundColor3 = i == 1 and Color3.fromRGB(70, 70, 70) or Color3.fromRGB(50, 50, 50)
		tab.BorderSizePixel = 0
		tab.Text = category
		tab.TextColor3 = Color3.fromRGB(255, 255, 255)
		tab.TextScaled = true
		tab.Font = Enum.Font.Gotham
		tab.Parent = tabFrame

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 4)
		tabCorner.Parent = tab

		tab.Activated:Connect(function()
			-- Update tab states
			for _, otherTab in tabs do
				otherTab.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
			end
			tab.BackgroundColor3 = Color3.fromRGB(70, 70, 70)

			-- Update selected category
			appState:Set("selectedCategory", category)
			self:_updateCustomizationContent(customizeFrame, category)
		end)

		tabs[category] = tab
	end

	-- Content area
	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "ContentFrame"
	contentFrame.Size = UDim2.new(1, -20, 1, -150)
	contentFrame.Position = UDim2.new(0, 10, 0, 110)
	contentFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 6
	contentFrame.Parent = customizeFrame

	local contentCorner = Instance.new("UICorner")
	contentCorner.CornerRadius = UDim.new(0, 6)
	contentCorner.Parent = contentFrame

	-- Initialize with first category
	appState:Set("selectedCategory", categories[1])
	self:_updateCustomizationContent(customizeFrame, categories[1])

	return customizeFrame
end

function AvatarStandClient:_createDetailsFrame(standId: string): Frame
	local standConfig = getStands()[standId]
	if not standConfig then
		warn(`Cannot create details frame for unknown stand: {standId}`)
		return Instance.new("Frame")
	end

	-- Modal background
	local modalBackground = Instance.new("Frame")
	modalBackground.Name = "DetailsModal"
	modalBackground.Size = UDim2.fromScale(1, 1)
	modalBackground.Position = UDim2.new(0, 0, 0, 0)
	modalBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	modalBackground.BackgroundTransparency = 0.5

	-- Details frame
	local detailsFrame = Instance.new("Frame")
	detailsFrame.Name = "DetailsFrame"
	detailsFrame.Size = UDim2.fromOffset(400, 300)
	detailsFrame.Position = UDim2.new(0.5, -200, 0.5, -150)
	detailsFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	detailsFrame.BorderSizePixel = 0
	detailsFrame.Parent = modalBackground

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, AvatarStandsConfig.UI_CONFIG.panelCornerRadius)
	corner.Parent = detailsFrame

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	header.BorderSizePixel = 0
	header.Parent = detailsFrame

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, AvatarStandsConfig.UI_CONFIG.panelCornerRadius)
	headerCorner.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Size = UDim2.new(1, -60, 1, 0)
	headerTitle.Position = UDim2.new(0, 15, 0, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = `Stand Details - {standConfig.standType or "Basic"}`
	headerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	headerTitle.TextScaled = true
	headerTitle.Font = Enum.Font.GothamBold
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Parent = header

	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(30, 30)
	closeButton.Position = UDim2.new(1, -40, 0.5, -15)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeButton.BorderSizePixel = 0
	closeButton.Text = "×"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextScaled = true
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = header

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 4)
	closeCorner.Parent = closeButton

	closeButton.Activated:Connect(function()
		modalBackground:Destroy()
		appState:Set("currentView", "Gallery")
	end)

	-- Info content
	local infoFrame = Instance.new("Frame")
	infoFrame.Name = "InfoFrame"
	infoFrame.Size = UDim2.new(1, -20, 1, -120)
	infoFrame.Position = UDim2.new(0, 10, 0, 70)
	infoFrame.BackgroundTransparency = 1
	infoFrame.Parent = detailsFrame

	local infoLayout = Instance.new("UIListLayout")
	infoLayout.SortOrder = Enum.SortOrder.LayoutOrder
	infoLayout.Padding = UDim.new(0, 8)
	infoLayout.Parent = infoFrame

	-- Create info labels
	local infoData = {
		{label = "Stand ID", value = standConfig.standId},
		{label = "Owner", value = `Player {standConfig.ownerId}`},
		{label = "Type", value = standConfig.standType or "Basic"},
		{label = "Position", value = `{math.floor(standConfig.position.X)}, {math.floor(standConfig.position.Y)}, {math.floor(standConfig.position.Z)}`},
		{label = "Created", value = DateTime.fromUnixTimestamp(standConfig.createdAt):FormatLocalTime("LLL dd, yyyy", "en-us")},
	}

	for i, info in infoData do
		local infoLabel = Instance.new("Frame")
		infoLabel.Name = info.label .. "Info"
		infoLabel.Size = UDim2.new(1, 0, 0, 25)
		infoLabel.BackgroundTransparency = 1
		infoLabel.LayoutOrder = i
		infoLabel.Parent = infoFrame

		local labelText = Instance.new("TextLabel")
		labelText.Size = UDim2.fromScale(0.4, 1)
		labelText.BackgroundTransparency = 1
		labelText.Text = info.label .. ":"
		labelText.TextColor3 = Color3.fromRGB(200, 200, 200)
		labelText.TextScaled = true
		labelText.Font = Enum.Font.Gotham
		labelText.TextXAlignment = Enum.TextXAlignment.Left
		labelText.Parent = infoLabel

		local valueText = Instance.new("TextLabel")
		valueText.Size = UDim2.fromScale(0.6, 1)
		valueText.Position = UDim2.fromScale(0.4, 0)
		valueText.BackgroundTransparency = 1
		valueText.Text = info.value
		valueText.TextColor3 = Color3.fromRGB(255, 255, 255)
		valueText.TextScaled = true
		valueText.Font = Enum.Font.Gotham
		valueText.TextXAlignment = Enum.TextXAlignment.Left
		valueText.Parent = infoLabel
	end

	-- Action buttons
	local buttonFrame = Instance.new("Frame")
	buttonFrame.Name = "ButtonFrame"
	buttonFrame.Size = UDim2.new(1, -20, 0, 40)
	buttonFrame.Position = UDim2.new(0, 10, 1, -50)
	buttonFrame.BackgroundTransparency = 1
	buttonFrame.Parent = detailsFrame

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.Padding = UDim.new(0, 10)
	buttonLayout.Parent = buttonFrame

	-- Edit button (only show if player can edit)
	local editButton = Instance.new("TextButton")
	editButton.Name = "EditButton"
	editButton.Size = UDim2.fromOffset(100, 35)
	editButton.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
	editButton.BorderSizePixel = 0
	editButton.Text = "Edit"
	editButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	editButton.TextScaled = true
	editButton.Font = Enum.Font.GothamBold
	editButton.Parent = buttonFrame

	local editCorner = Instance.new("UICorner")
	editCorner.CornerRadius = UDim.new(0, 4)
	editCorner.Parent = editButton

	editButton.Activated:Connect(function()
		modalBackground:Destroy()
		self:enterEditMode(standId)
	end)

	-- Customize button
	local customizeButton = Instance.new("TextButton")
	customizeButton.Name = "CustomizeButton"
	customizeButton.Size = UDim2.fromOffset(100, 35)
	customizeButton.BackgroundColor3 = Color3.fromRGB(150, 50, 200)
	customizeButton.BorderSizePixel = 0
	customizeButton.Text = "Customize"
	customizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	customizeButton.TextScaled = true
	customizeButton.Font = Enum.Font.GothamBold
	customizeButton.Parent = buttonFrame

	local customizeCorner = Instance.new("UICorner")
	customizeCorner.CornerRadius = UDim.new(0, 4)
	customizeCorner.Parent = customizeButton

	customizeButton.Activated:Connect(function()
		modalBackground:Destroy()
		self:openStandCustomization(standId)
	end)

	-- Click background to close
	modalBackground.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and input.Target == modalBackground then
			modalBackground:Destroy()
			appState:Set("currentView", "Gallery")
		end
	end)

	return modalBackground
end

function AvatarStandClient:_showInteractionPrompt(standId: string)
	if not standInteractionUI then return end

	self:setActiveStand(standId)

	-- Update title with stand info
	local standConfig = getStands()[standId]
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
	local editFrame = self:_createEditFrame(standId)
	editFrame.Parent = mainFrame
	maid:Give(editFrame)

	-- Animate in
	editFrame.Position = UDim2.new(0.5, -200, -1, 0)
	local slideInTween = TweenService:Create(
		editFrame,
		TweenInfo.new(AvatarStandsConfig.UI_CONFIG.fadeInDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Position = UDim2.new(0.5, -200, 0.5, -200)}
	)
	slideInTween:Play()
end

function AvatarStandClient:_hideEditUI()
	local editFrame = mainFrame and mainFrame:FindFirstChild("EditFrame")
	if not editFrame then return end

	local slideOutTween = TweenService:Create(
		editFrame,
		TweenInfo.new(AvatarStandsConfig.UI_CONFIG.fadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Position = UDim2.new(0.5, -200, -1, 0)}
	)
	slideOutTween:Play()
	slideOutTween.Completed:Connect(function()
		editFrame:Destroy()
	end)
end

function AvatarStandClient:_showCustomizationUI(standId: string)
	local customizeFrame = self:_createCustomizeFrame(standId)
	customizeFrame.Parent = mainFrame
	maid:Give(customizeFrame)

	-- Animate in from right
	customizeFrame.Position = UDim2.new(1.5, 0, 0.5, -250)
	local slideInTween = TweenService:Create(
		customizeFrame,
		TweenInfo.new(AvatarStandsConfig.UI_CONFIG.fadeInDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Position = UDim2.new(0.5, -250, 0.5, -250)}
	)
	slideInTween:Play()
end

function AvatarStandClient:_showDetailsUI(standId: string)
	local detailsFrame = self:_createDetailsFrame(standId)
	detailsFrame.Parent = mainFrame
	maid:Give(detailsFrame)

	-- Animate in with fade
	detailsFrame.BackgroundTransparency = 1
	local fadeInTween = TweenService:Create(
		detailsFrame,
		TweenInfo.new(AvatarStandsConfig.UI_CONFIG.fadeInDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0.1}
	)
	fadeInTween:Play()
end

function AvatarStandClient:_setupStateConnections()
	-- React to individual state changes and fire combined UI state events
	local function fireUIStateChanged()
		Signal.FireLocal(CLIENT_EVENTS.UI_STATE_CHANGED, getUIState())
	end

	maid:Give(appState:OnChange("activeStandId", fireUIStateChanged))
	maid:Give(appState:OnChange("isEditMode", fireUIStateChanged))
	maid:Give(appState:OnChange("isCustomizing", fireUIStateChanged))
	maid:Give(appState:OnChange("selectedCategory", fireUIStateChanged))
	maid:Give(appState:OnChange("currentView", fireUIStateChanged))

	maid:Give(appState:OnChange("stands", function(newStands)
		Signal.FireLocal(CLIENT_EVENTS.STAND_DATA_RECEIVED, newStands)
	end))
end

function AvatarStandClient:_setupInputHandling()
	-- Handle escape key to close UIs
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.Escape then
			if isInEditMode() then
				self:exitEditMode()
			elseif standInteractionUI and standInteractionUI.Visible then
				self:_hideInteractionPrompt()
			end
		end
	end)
end

function AvatarStandClient:_setupNetworking()
	-- Listen for stand data from server
	maid:Give(Signal.OnClient(RemoteIds.STAND_DATA_SYNC, function(standId: string, standConfig: StandConfig)
		self:_updateStandData(standId, standConfig)
	end))

	-- Listen for interaction zone state changes
	maid:Give(Signal.OnClient(RemoteIds.INTERACTION_ZONE_STATE, function(standId: string, state: string)
		if state == "entered" then
			self:onStandInteractionZoneEntered(standId)
		elseif state == "exited" then
			self:onStandInteractionZoneExited(standId)
		end
	end))

	-- Listen for stand creation events
	maid:Give(Signal.OnClient(RemoteIds.STAND_CREATED, function(standId: string, standConfig: StandConfig)
		self:_updateStandData(standId, standConfig)
		print(`New stand created: {standId}`)
	end))

	-- Listen for stand removal events
	maid:Give(Signal.OnClient(RemoteIds.STAND_REMOVED, function(standId: string)
		self:_removeStandData(standId)
		print(`Stand removed: {standId}`)
	end))

	-- Listen for stand updates
	maid:Give(Signal.OnClient(RemoteIds.STAND_UPDATED, function(standId: string, standConfig: StandConfig)
		self:_updateStandData(standId, standConfig)
		print(`Stand updated: {standId}`)
	end))

	-- Listen for avatar updates
	maid:Give(Signal.OnClient(RemoteIds.AVATAR_UPDATED, function(standId: string, avatarData: any)
		local currentStands = getStands()
		if currentStands[standId] then
			-- Update the avatar data for this stand
			currentStands[standId].avatarData = avatarData
			appState:Set("stands", currentStands)
			print(`Avatar updated for stand: {standId}`)
		end
	end))

	-- Set up creation system networking
	self:_setupCreationNetworking()

	-- Request initial stand data when client starts
	self:requestNearbyStands()
end

function AvatarStandClient:_setupCreationNetworking()
	-- Listen for permission check responses
	maid:Give(Signal.OnClient(RemoteIds.PERMISSION_CHECK_RESPONSE, function(hasPermission: boolean)
		appState:Set("hasCreationPermissions", hasPermission)
		self:_updateCreationUI(hasPermission)
	end))

	-- Listen for stand creation responses
	maid:Give(Signal.OnClient(RemoteIds.CREATE_STAND_RESPONSE, function(success: boolean, message: string, standId: string?)
		if success and standId then
			print(`Stand created successfully: {standId}`)
			self:_hideCreationWizard()
			-- Auto-show the new stand details
			task.wait(0.5) -- Small delay to let the stand data sync
			self:showStandDetails(standId)
		else
			warn(`Stand creation failed: {message}`)
			self:_showCreationError(message)
		end
	end))

	-- Check permissions on startup
	self:_checkCreationPermissions()

	-- Create creation UI
	self:_createCreationUI()
end

function AvatarStandClient:_checkCreationPermissions()
	Signal.FireServer(RemoteIds.CHECK_PERMISSIONS)
end

function AvatarStandClient:_createCreationUI()
	-- Create floating "Create Stand" button
	createStandButton = Instance.new("TextButton")
	createStandButton.Name = "CreateStandButton"
	createStandButton.Size = UDim2.fromOffset(120, 40)
	createStandButton.Position = UDim2.new(1, -140, 0, 20)
	createStandButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
	createStandButton.BorderSizePixel = 0
	createStandButton.Text = "Create Stand"
	createStandButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	createStandButton.TextScaled = true
	createStandButton.Font = Enum.Font.GothamBold
	createStandButton.Visible = false -- Hidden until permissions are checked
	createStandButton.Parent = mainFrame

	-- Add corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = createStandButton

	-- Button click handler
	createStandButton.Activated:Connect(function()
		self:_showCreationWizard()
	end)

	maid:Give(createStandButton)
end

function AvatarStandClient:_updateCreationUI(hasPermission: boolean)
	if createStandButton then
		createStandButton.Visible = hasPermission
	end
end

function AvatarStandClient:_showCreationWizard()
	print("Creation wizard placeholder")
	-- TODO: Implement creation wizard
end

function AvatarStandClient:_hideCreationWizard()
	print("Hide creation wizard")
	-- TODO: Implement creation wizard
end

function AvatarStandClient:_showCreationError(message: string)
	warn("Creation error:", message)
	-- TODO: Show error to user
end

-- Helper methods for networking

function AvatarStandClient:_updateStandData(standId: string, standConfig: StandConfig)
	local currentStands = getStands()
	currentStands[standId] = standConfig
	appState:Set("stands", currentStands)
end

function AvatarStandClient:_removeStandData(standId: string)
	local currentStands = getStands()
	currentStands[standId] = nil
	appState:Set("stands", currentStands)

	-- If this was the active stand, clear it
	if getActiveStandId() == standId then
		appState:Set("activeStandId", nil)
		self:exitEditMode()
	end
end

function AvatarStandClient:requestStandData(standId: string?)
	Signal.FireServer(RemoteIds.REQUEST_STAND_DATA, standId)
end

function AvatarStandClient:requestNearbyStands(range: number?)
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
		local position = LocalPlayer.Character.HumanoidRootPart.Position
		Signal.FireServer(RemoteIds.REQUEST_NEARBY_STANDS, position, range or 100)
	end
end

function AvatarStandClient:interactWithStand(standId: string, interactionType: string)
	Signal.FireServer(RemoteIds.INTERACT_WITH_STAND, standId, interactionType)
end

function AvatarStandClient:updateStandConfig(standId: string, newConfig: StandConfig)
	Signal.FireServer(RemoteIds.UPDATE_STAND_CONFIG, standId, newConfig)
end

function AvatarStandClient:updateAvatarData(standId: string, avatarData: any)
	Signal.FireServer(RemoteIds.UPDATE_AVATAR_DATA, standId, avatarData)
end

-- Update the button action handler to use networking
function AvatarStandClient:_handleButtonAction(action: string)
	local activeId = getActiveStandId()

	if action == "view" and activeId then
		self:interactWithStand(activeId, "view")
		self:showStandDetails(activeId)
	elseif action == "edit" and activeId then
		self:interactWithStand(activeId, "edit")
		self:enterEditMode(activeId)
	elseif action == "customize" and activeId then
		self:interactWithStand(activeId, "customize")
		self:openStandCustomization(activeId)
	elseif action == "close" then
		self:_hideInteractionPrompt()
	end
end

-- Helper methods for UI creation

function AvatarStandClient:_createEditSection(parent: ScrollingFrame, title: string, yOffset: number): Frame
	local section = Instance.new("Frame")
	section.Name = title .. "Section"
	section.Size = UDim2.new(1, -10, 0, 100)
	section.Position = UDim2.new(0, 5, 0, yOffset)
	section.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	section.BorderSizePixel = 0
	section.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = section

	local sectionTitle = Instance.new("TextLabel")
	sectionTitle.Name = "SectionTitle"
	sectionTitle.Size = UDim2.new(1, -10, 0, 25)
	sectionTitle.Position = UDim2.new(0, 5, 0, 5)
	sectionTitle.BackgroundTransparency = 1
	sectionTitle.Text = title
	sectionTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	sectionTitle.TextScaled = true
	sectionTitle.Font = Enum.Font.GothamBold
	sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
	sectionTitle.Parent = section

	return section
end

function AvatarStandClient:_createNumberInput(parent: Frame, labelText: string, defaultValue: number): TextBox
	local inputFrame = Instance.new("Frame")
	inputFrame.Name = labelText .. "InputFrame"
	inputFrame.Size = UDim2.new(1, -10, 0, 25)
	inputFrame.BackgroundTransparency = 1
	inputFrame.Parent = parent

	-- Auto-position using UIListLayout if not present
	if not parent:FindFirstChild("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 5)
		layout.Parent = parent
	end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.4, 1)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.TextScaled = true
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = inputFrame

	local textBox = Instance.new("TextBox")
	textBox.Size = UDim2.fromScale(0.6, 1)
	textBox.Position = UDim2.fromScale(0.4, 0)
	textBox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	textBox.BorderSizePixel = 0
	textBox.Text = tostring(defaultValue)
	textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	textBox.TextScaled = true
	textBox.Font = Enum.Font.Gotham
	textBox.PlaceholderText = "Enter number..."
	textBox.Parent = inputFrame

	local textBoxCorner = Instance.new("UICorner")
	textBoxCorner.CornerRadius = UDim.new(0, 4)
	textBoxCorner.Parent = textBox

	return textBox
end

function AvatarStandClient:_createDropdown(parent: Frame, labelText: string, defaultValue: string, options: {string}): TextButton
	local dropdownFrame = Instance.new("Frame")
	dropdownFrame.Name = labelText .. "DropdownFrame"
	dropdownFrame.Size = UDim2.new(1, -10, 0, 25)
	dropdownFrame.BackgroundTransparency = 1
	dropdownFrame.Parent = parent

	-- Auto-position using UIListLayout if not present
	if not parent:FindFirstChild("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 5)
		layout.Parent = parent
	end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.4, 1)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.TextScaled = true
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = dropdownFrame

	local dropdown = Instance.new("TextButton")
	dropdown.Size = UDim2.fromScale(0.6, 1)
	dropdown.Position = UDim2.fromScale(0.4, 0)
	dropdown.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	dropdown.BorderSizePixel = 0
	dropdown.Text = defaultValue
	dropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
	dropdown.TextScaled = true
	dropdown.Font = Enum.Font.Gotham
	dropdown.Parent = dropdownFrame

	local dropdownCorner = Instance.new("UICorner")
	dropdownCorner.CornerRadius = UDim.new(0, 4)
	dropdownCorner.Parent = dropdown

	-- Simple cycling behavior for demo
	local currentIndex = 1
	for i, option in options do
		if option == defaultValue then
			currentIndex = i
			break
		end
	end

	dropdown.Activated:Connect(function()
		currentIndex = currentIndex % #options + 1
		dropdown.Text = options[currentIndex]
	end)

	return dropdown
end

function AvatarStandClient:_updateCustomizationContent(customizeFrame: Frame, category: string)
	local contentFrame = customizeFrame:FindFirstChild("ContentFrame")
	if not contentFrame then return end

	-- Clear existing content
	for _, child in contentFrame:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "UICorner" then
			child:Destroy()
		end
	end

	-- Create loading indicator
	local loadingLabel = Instance.new("TextLabel")
	loadingLabel.Size = UDim2.new(1, -20, 0, 50)
	loadingLabel.Position = UDim2.new(0, 10, 0, 10)
	loadingLabel.BackgroundTransparency = 1
	loadingLabel.Text = `Loading {category} items...`
	loadingLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
	loadingLabel.TextScaled = true
	loadingLabel.Font = Enum.Font.Gotham
	loadingLabel.Parent = contentFrame

	-- Load catalog items for category
	self:_loadCatalogItems(category):andThen(function(items)
		if loadingLabel.Parent then
			loadingLabel:Destroy()
		end

		self:_renderCatalogItems(contentFrame, items, category)
	end):catch(function(err)
		if loadingLabel.Parent then
			loadingLabel.Text = `Failed to load {category} items: {err}`
			loadingLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		end
	end)
end

-- Load catalog items using MarketplaceService and AvatarEditorService
function AvatarStandClient:_loadCatalogItems(category: string): Promise<{any}>
	return Promise.new(function(resolve, reject)
		local MarketplaceService = game:GetService("MarketplaceService")
		local AvatarEditorService = game:GetService("AvatarEditorService")

		-- Map categories to Roblox asset types
		local categoryToAssetType = {
			Shirts = Enum.AvatarAssetType.Shirt,
			Pants = Enum.AvatarAssetType.Pants,
			Accessories = Enum.AvatarAssetType.Hat, -- Most common accessory type
			Hair = Enum.AvatarAssetType.Hair,
			Face = Enum.AvatarAssetType.Face,
			["Body Colors"] = nil, -- Special case - handled differently
		}

		if category == "Body Colors" then
			-- For body colors, create predefined options
			local bodyColors = {
				{name = "Light", bodyColors = {
					headColor = Color3.fromRGB(254, 219, 205),
					torsoColor = Color3.fromRGB(254, 219, 205),
					leftArmColor = Color3.fromRGB(254, 219, 205),
					rightArmColor = Color3.fromRGB(254, 219, 205),
					leftLegColor = Color3.fromRGB(254, 219, 205),
					rightLegColor = Color3.fromRGB(254, 219, 205),
				}},
				{name = "Medium", bodyColors = {
					headColor = Color3.fromRGB(217, 178, 140),
					torsoColor = Color3.fromRGB(217, 178, 140),
					leftArmColor = Color3.fromRGB(217, 178, 140),
					rightArmColor = Color3.fromRGB(217, 178, 140),
					leftLegColor = Color3.fromRGB(217, 178, 140),
					rightLegColor = Color3.fromRGB(217, 178, 140),
				}},
				{name = "Dark", bodyColors = {
					headColor = Color3.fromRGB(138, 86, 62),
					torsoColor = Color3.fromRGB(138, 86, 62),
					leftArmColor = Color3.fromRGB(138, 86, 62),
					rightArmColor = Color3.fromRGB(138, 86, 62),
					leftLegColor = Color3.fromRGB(138, 86, 62),
					rightLegColor = Color3.fromRGB(138, 86, 62),
				}},
			}
			resolve(bodyColors)
			return
		end

		local assetType = categoryToAssetType[category]
		if not assetType then
			reject(`Unknown category: {category}`)
			return
		end

		-- Get catalog items - using pcall to handle potential API errors
		local success, result = pcall(function()
			return AvatarEditorService:SearchCatalog({
				AssetTypes = {assetType},
				Bundle = false,
				CategoryFilter = Enum.CatalogCategoryFilter.None,
				MaxPrice = 0, -- Free items only for demo
				MinPrice = 0,
				SortType = Enum.CatalogSortType.MostFavorited,
				SearchKeyword = "",
				IncludeOffSale = false,
			})
		end)

		if success and result then
			-- Convert to our format and limit results
			local items = {}
			local maxItems = math.min(20, #result.Results) -- Show up to 20 items

			for i = 1, maxItems do
				local item = result.Results[i]
				table.insert(items, {
					id = item.Id,
					name = item.Name,
					assetType = assetType,
					price = item.Price or 0,
					creatorName = item.Creator and item.Creator.Name or "Unknown",
				})
			end

			resolve(items)
		else
			-- Fallback to mock data if API fails
			local mockItems = {}
			for i = 1, 6 do
				table.insert(mockItems, {
					id = 1000000 + i,
					name = `{category} Item {i}`,
					assetType = assetType,
					price = 0,
					creatorName = "Roblox",
				})
			end
			resolve(mockItems)
		end
	end)
end

-- Render catalog items in the content frame
function AvatarStandClient:_renderCatalogItems(contentFrame: ScrollingFrame, items: {any}, category: string)
	local GridLayout = Instance.new("UIGridLayout")
	GridLayout.CellSize = UDim2.fromOffset(120, 150)
	GridLayout.CellPadding = UDim2.fromOffset(10, 10)
	GridLayout.SortOrder = Enum.SortOrder.Name
	GridLayout.Parent = contentFrame

	local Padding = Instance.new("UIPadding")
	Padding.PaddingAll = UDim.new(0, 10)
	Padding.Parent = contentFrame

	-- Create item frames
	for _, item in ipairs(items) do
		local itemFrame = self:_createCatalogItemFrame(item, category)
		itemFrame.Parent = contentFrame
	end

	-- Update canvas size based on grid layout
	local itemsPerRow = math.floor((contentFrame.AbsoluteSize.X - 20) / 130) -- Account for padding and spacing
	itemsPerRow = math.max(1, itemsPerRow)
	local rowCount = math.ceil(#items / itemsPerRow)
	local canvasHeight = rowCount * 160 + 20 -- Grid height + padding

	contentFrame.CanvasSize = UDim2.fromOffset(0, canvasHeight)
end

-- Create individual catalog item frame
function AvatarStandClient:_createCatalogItemFrame(item: any, category: string): Frame
	local itemFrame = Instance.new("Frame")
	itemFrame.Size = UDim2.fromOffset(120, 150)
	itemFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
	itemFrame.BorderSizePixel = 0

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 6)
	Corner.Parent = itemFrame

	-- Item preview (thumbnail)
	local thumbnail = Instance.new("ImageLabel")
	thumbnail.Size = UDim2.new(1, -10, 0, 80)
	thumbnail.Position = UDim2.new(0, 5, 0, 5)
	thumbnail.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	thumbnail.BorderSizePixel = 0
	thumbnail.Image = "" -- Would need MarketplaceService:GetProductInfo() for real thumbnails
	thumbnail.ScaleType = Enum.ScaleType.Fit
	thumbnail.Parent = itemFrame

	local ThumbCorner = Instance.new("UICorner")
	ThumbCorner.CornerRadius = UDim.new(0, 4)
	ThumbCorner.Parent = thumbnail

	-- Item name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -10, 0, 35)
	nameLabel.Position = UDim2.new(0, 5, 0, 90)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = item.name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextWrapped = true
	nameLabel.Parent = itemFrame

	-- Apply button
	local applyButton = Instance.new("TextButton")
	applyButton.Size = UDim2.new(1, -10, 0, 20)
	applyButton.Position = UDim2.new(0, 5, 1, -25)
	applyButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
	applyButton.BorderSizePixel = 0
	applyButton.Text = "Apply"
	applyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	applyButton.TextScaled = true
	applyButton.Font = Enum.Font.GothamBold
	applyButton.Parent = itemFrame

	local ButtonCorner = Instance.new("UICorner")
	ButtonCorner.CornerRadius = UDim.new(0, 4)
	ButtonCorner.Parent = applyButton

	-- Apply button functionality
	maid:Give(applyButton.Activated:Connect(function()
		self:_applyCatalogItem(item, category)
	end))

	-- Hover effects
	maid:Give(itemFrame.MouseEnter:Connect(function()
		itemFrame.BackgroundColor3 = Color3.fromRGB(55, 55, 60)
		applyButton.BackgroundColor3 = Color3.fromRGB(0, 140, 220)
	end))

	maid:Give(itemFrame.MouseLeave:Connect(function()
		itemFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
		applyButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
	end))

	return itemFrame
end

-- Apply catalog item to the current avatar stand
function AvatarStandClient:_applyCatalogItem(item: any, category: string)
	local activeStandId = getActiveStandId()
	if not activeStandId then
		warn("No active stand to apply item to")
		return
	end

	-- Send customization update to server
	if category == "Body Colors" then
		Signal.FireServer(RemoteIds.UPDATE_AVATAR_DISPLAY, activeStandId, {
			bodyColors = item.bodyColors
		})
	else
		Signal.FireServer(RemoteIds.UPDATE_AVATAR_DISPLAY, activeStandId, {
			assetId = item.id,
			assetType = item.assetType,
			category = category
		})
	end

	print(`Applied {item.name} to stand {activeStandId}`)
end

-- Export module state for external use
AvatarStandClient.State = {
	appState = appState,
	getUIState = getUIState,
	getStands = getStands,
	getActiveStandId = getActiveStandId,
	isInEditMode = isInEditMode,
	getCurrentView = getCurrentView,
	hasCreationPerms = hasCreationPerms,
}

return AvatarStandClient