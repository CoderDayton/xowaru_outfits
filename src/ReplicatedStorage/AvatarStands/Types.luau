--!strict
--[[
	Avatar Stands Types
	Comprehensive type definitions for the server-owned Avatar Stands system

	ARCHITECTURE OVERVIEW:
	- All stands are server-owned and persist across sessions
	- No player ownership - stands are managed by the system
	- Data persistence through DataStore integration
	- Optimized event broadcasting to minimize client traffic
]]

-- Core Stand Configuration (Server-Owned)
export type StandConfig = {
	standId: string,
	standName: string,
	position: Vector3,
	rotation: Vector3?,
	scale: Vector3?,
	isActive: boolean,
	-- Removed creatorId - all stands are server-owned
	permissions: StandPermissions,
	displaySettings: DisplaySettings,
	createdAt: number,
	lastUpdated: number,
	-- Persistence metadata
	isPersistent: boolean, -- Whether this stand should persist across sessions
	version: number, -- For data migration purposes
}

export type StandPermissions = {
	canView: boolean,
	canInteract: boolean,
	-- Removed player-based permissions since stands are server-owned
	allowedUsers: { number }?, -- Optional: specific users who can interact
	blockedUsers: { number }?, -- Optional: users who cannot interact
	-- System-level permissions
	isSystemStand: boolean, -- Whether this is a core system stand
	maintenanceMode: boolean, -- Whether stand is in maintenance
}

export type DisplaySettings = {
	avatarRotationSpeed: number,
	showNameplate: boolean,
	showOutfitDetails: boolean,
	lightingPreset: LightingPreset,
	cameraDistance: number,
	cameraHeight: number,
}

export type LightingPreset = "Bright" | "Dramatic" | "Soft" | "Natural" | "Studio"

-- Avatar Display Data
export type AvatarDisplay = {
	standId: string,
	standName: string,
	displayName: string?,
	outfitId: number?,
	accessories: { AccessoryInfo },
	bodyColors: BodyColors?,
	scales: BodyScales?,
	-- Body part asset IDs for custom avatar loading
	headId: number?,
	torsoId: number?,
	leftArmId: number?,
	rightArmId: number?,
	leftLegId: number?,
	rightLegId: number?,
	lastUpdated: number,
}

export type AccessoryInfo = {
	assetId: number,
	accessoryType: Enum.AccessoryType,
	attachmentPoint: string?,
}

export type BodyColors = {
	HeadColor3: Color3?,
	LeftArmColor3: Color3?,
	LeftLegColor3: Color3?,
	RightArmColor3: Color3?,
	RightLegColor3: Color3?,
	TorsoColor3: Color3?,
}

export type BodyScales = {
	BodyDepthScale: number?,
	BodyHeightScale: number?,
	BodyProportionScale: number?,
	BodyTypeScale: number?,
	BodyWidthScale: number?,
	HeadScale: number?,
}

-- Stand Interaction Data
export type InteractionZone = {
	standId: string,
	range: number,
	height: number,
	position: Vector3,
	isActive: boolean,
}

export type StandInteraction = {
	standId: string,
	playerId: number,
	interactionType: InteractionType,
	timestamp: number,
	data: { [string]: any }?,
}

export type InteractionType = "View" | "Share" | "Report" | "Favorite" -- Server Events
export type StandServerEvents = {
	StandCreated: (standConfig: StandConfig) -> (),
	StandUpdated: (standId: string, changes: { [string]: any }) -> (),
	StandRemoved: (standId: string) -> (),
	PlayerEnteredZone: (playerId: number, standId: string) -> (),
	PlayerExitedZone: (playerId: number, standId: string) -> (),
	InteractionRequested: (interaction: StandInteraction) -> (),
}

-- Client Events
export type StandClientEvents = {
	StandDataReceived: (stands: { [string]: StandConfig }) -> (),
	StandUpdated: (standId: string, newConfig: StandConfig) -> (),
	InteractionZoneEntered: (standId: string) -> (),
	InteractionZoneExited: (standId: string) -> (),
	UIStateChanged: (newState: UIState) -> (),
}

-- UI State Management
export type UIState = {
	activeStandId: string?,
	currentView: ViewMode,
}

export type ViewMode = "Gallery" | "Detailed"

-- Network Communication
export type NetworkRequest = {
	requestId: string,
	action: string,
	data: { [string]: any },
	timestamp: number,
}

export type NetworkResponse = {
	requestId: string,
	success: boolean,
	data: { [string]: any }?,
	error: string?,
	timestamp: number,
}

-- Data Persistence Types
export type PersistedStandData = {
	standConfig: StandConfig,
	avatarData: AvatarDisplay?,
	metadata: PersistenceMetadata,
}

export type PersistenceMetadata = {
	lastSaved: number,
	saveVersion: number,
	checksum: string?, -- For data integrity verification
	backupCount: number, -- Number of backups created
}

-- System Architecture Documentation Types
export type SystemComponent = {
	name: string,
	description: string,
	dependencies: { string },
	responsibilities: { string },
	dataStructures: { string },
}

export type DataStructureDoc = {
	name: string,
	purpose: string,
	keyFields: { [string]: string }, -- field name -> description
	relationships: { string }, -- Related data structures
	persistence: boolean, -- Whether persisted to DataStore
	memoryUsage: string, -- Estimated memory footprint
}

-- Performance Tracking
export type PerformanceMetrics = {
	standId: string,
	loadTime: number,
	renderTime: number,
	memoryUsage: number,
	lastMeasured: number,
}

return {}
