--!strict
--[[
	Remote Signal IDs for Avatar Stands System
	
	Centralized definition of all client-server communication events.
	Used by both server (AvatarStandManager) and client (AvatarStandClient).
]]

-- Server -> Client Events (server broadcasts to clients)
export type ServerToClientEvents = {
	-- Global broadcasts (all clients need to know)
	STAND_CREATED: "AvatarStand_StandCreated",
	STAND_REMOVED: "AvatarStand_StandRemoved",
	
	-- Proximity broadcasts (only nearby clients)
	STAND_UPDATED: "AvatarStand_StandUpdated",
	AVATAR_UPDATED: "AvatarStand_AvatarUpdated",
	PLAYER_ENTERED_ZONE: "AvatarStand_PlayerEnteredZone",
	PLAYER_EXITED_ZONE: "AvatarStand_PlayerExitedZone",
	
	-- Individual client updates
	STAND_DATA_SYNC: "AvatarStand_StandDataSync", -- Full stand data for new clients
	INTERACTION_ZONE_STATE: "AvatarStand_InteractionZoneState", -- Zone enter/exit for specific player
}

-- Client -> Server Events (client requests to server)
export type ClientToServerEvents = {
	-- Data requests
	REQUEST_STAND_DATA: "AvatarStand_RequestStandData", -- Request stand data for specific stand or all stands
	REQUEST_NEARBY_STANDS: "AvatarStand_RequestNearbyStands", -- Request stands within range of player
	
	-- Stand interactions
	INTERACT_WITH_STAND: "AvatarStand_InteractWithStand", -- Player wants to interact with stand
	UPDATE_STAND_CONFIG: "AvatarStand_UpdateStandConfig", -- Admin/editor updates stand configuration
	UPDATE_AVATAR_DATA: "AvatarStand_UpdateAvatarData", -- Update avatar display on stand
	
	-- Zone management
	PLAYER_POSITION_UPDATE: "AvatarStand_PlayerPositionUpdate", -- Player position for proximity calculations
}

-- Combined event IDs for easy access
local REMOTE_IDS = {
	-- Server to Client
	STAND_CREATED = "AvatarStand_StandCreated",
	STAND_REMOVED = "AvatarStand_StandRemoved",
	STAND_UPDATED = "AvatarStand_StandUpdated",
	AVATAR_UPDATED = "AvatarStand_AvatarUpdated",
	PLAYER_ENTERED_ZONE = "AvatarStand_PlayerEnteredZone",
	PLAYER_EXITED_ZONE = "AvatarStand_PlayerExitedZone",
	STAND_DATA_SYNC = "AvatarStand_StandDataSync",
	INTERACTION_ZONE_STATE = "AvatarStand_InteractionZoneState",
	
	-- Creation & Permission Events
	PERMISSION_CHECK_RESPONSE = "AvatarStand_PermissionCheckResponse",
	CREATE_STAND_RESPONSE = "AvatarStand_CreateStandResponse",
	
	-- Client to Server
	REQUEST_STAND_DATA = "AvatarStand_RequestStandData",
	REQUEST_NEARBY_STANDS = "AvatarStand_RequestNearbyStands",
	INTERACT_WITH_STAND = "AvatarStand_InteractWithStand",
	UPDATE_STAND_CONFIG = "AvatarStand_UpdateStandConfig",
	UPDATE_AVATAR_DATA = "AvatarStand_UpdateAvatarData",
	UPDATE_AVATAR_DISPLAY = "AvatarStand_UpdateAvatarDisplay", -- Catalog customization updates
	PLAYER_POSITION_UPDATE = "AvatarStand_PlayerPositionUpdate",
	
	-- Creation & Permission Requests
	CHECK_PERMISSIONS = "AvatarStand_CheckPermissions",
	CREATE_STAND_REQUEST = "AvatarStand_CreateStandRequest",
}

return REMOTE_IDS