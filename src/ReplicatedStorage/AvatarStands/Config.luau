--!strict
--[[
	Avatar Stands Configuration
	Central configuration for all Avatar Stands functionality
]]

local Types = require(script.Parent.Types)

type StandConfig = Types.StandConfig
type LightingPreset = Types.LightingPreset

-- Default Stand Configuration
local DEFAULT_STAND_CONFIG = {
	interactionRange = 12,
	rotationSpeed = 0.8,
	cameraDistance = 10,
	cameraHeight = 3,
	lightingPreset = "Natural" :: LightingPreset,
	permissions = {
		canView = true,
		canInteract = true,
	},
}-- Lighting Presets
local LIGHTING_PRESETS = {
	Bright = {
		ambient = Color3.fromRGB(200, 200, 200),
		brightness = 2.0,
		shadowSoftness = 0.2,
		exposure = 1.2,
	},

	Dramatic = {
		ambient = Color3.fromRGB(50, 50, 80),
		brightness = 3.0,
		shadowSoftness = 0.8,
		exposure = 0.8,
	},

	Soft = {
		ambient = Color3.fromRGB(150, 150, 160),
		brightness = 1.5,
		shadowSoftness = 0.4,
		exposure = 1.0,
	},

	Natural = {
		ambient = Color3.fromRGB(120, 120, 140),
		brightness = 1.8,
		shadowSoftness = 0.3,
		exposure = 1.1,
	},

	Studio = {
		ambient = Color3.fromRGB(180, 180, 190),
		brightness = 2.5,
		shadowSoftness = 0.1,
		exposure = 1.3,
	},
}

-- Performance Settings
local PERFORMANCE_CONFIG = {
	maxVisibleStands = 20,
	cullingDistance = 100,
	lodDistance = 50,
	updateInterval = 0.1,
	maxConcurrentLoads = 5,
}

-- UI Configuration
local UI_CONFIG = {
	animationDuration = 0.3,
	fadeInDuration = 0.5,
	fadeOutDuration = 0.2,
	buttonHoverScale = 1.1,
	panelCornerRadius = 8,
	defaultTweenInfo = TweenInfo.new(
		0.3,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	),
}

-- Network Configuration
local NETWORK_CONFIG = {
	requestTimeout = 10,
	maxRetries = 3,
	retryDelay = 1,
	batchSize = 10,
}

-- Validation Rules
local VALIDATION_RULES = {
	standId = {
		minLength = 3,
		maxLength = 50,
		pattern = "^[a-zA-Z0-9_-]+$",
	},
	username = {
		minLength = 1,
		maxLength = 20,
	},
	interactionRange = {
		min = 5,
		max = 50,
	},
	rotationSpeed = {
		min = 0,
		max = 5,
	},
}

local Config = {
	DEFAULT_STAND_CONFIG = DEFAULT_STAND_CONFIG,
	LIGHTING_PRESETS = LIGHTING_PRESETS,
	PERFORMANCE_CONFIG = PERFORMANCE_CONFIG,
	UI_CONFIG = UI_CONFIG,
	NETWORK_CONFIG = NETWORK_CONFIG,
	VALIDATION_RULES = VALIDATION_RULES,
}

-- Utility Functions
function Config.getStandConfig(): typeof(DEFAULT_STAND_CONFIG)
	return DEFAULT_STAND_CONFIG
end

function Config.getLightingPreset(presetName: LightingPreset): typeof(LIGHTING_PRESETS.Natural)
	return LIGHTING_PRESETS[presetName] or LIGHTING_PRESETS.Natural
end

function Config.validateStandId(standId: string): boolean
	local rules = VALIDATION_RULES.standId
	return #standId >= rules.minLength
		and #standId <= rules.maxLength
		and string.match(standId, rules.pattern) ~= nil
end

function Config.validateInteractionRange(range: number): boolean
	local rules = VALIDATION_RULES.interactionRange
	return range >= rules.min and range <= rules.max
end

return Config
