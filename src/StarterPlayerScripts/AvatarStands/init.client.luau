--!strict
--[[
	Avatar Stands Client Initialization
	Starts the Avatar Stand client system when the player joins
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for all required modules to load
local AvatarStandClient = require(script.AvatarStandClient)

-- Initialize the client system
local client = AvatarStandClient.new()

-- Store global reference for debugging
_G.AvatarStandClient = client

print("Avatar Stands Client initialized")