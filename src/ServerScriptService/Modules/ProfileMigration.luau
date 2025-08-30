local PlayerData = require(script.Parent.PlayerData)

export type Profile = PlayerData.Profile

local ProfileMigration = {}

ProfileMigration.CURRENT_SCHEMA = 1

-- Migration functions for each schema version
ProfileMigration.Migrations = {
	[1] = function(profile: Profile): Profile
		profile.SchemaVersion = 1
        profile.JoinCount = profile.JoinCount or 0
        profile.LastSeen = profile.LastSeen or 0
		return profile
	end,
	-- Add more migrations as needed:
	-- [2] = function(profile: Profile): Profile
	--     profile.SchemaVersion = 2
	--     profile.NewField = "default_value"
	--     return profile
	-- end,
}

-- Rollback functions for each schema version (reverse migrations)
ProfileMigration.Rollbacks = {
	[1] = function(profile: Profile): Profile
		-- Example rollback from schema 1 to 0
		-- Remove any fields added in schema 1
		profile.SchemaVersion = 0
		return profile
	end,
	-- Add more rollbacks as needed:
	-- [2] = function(profile: Profile): Profile
	--     profile.SchemaVersion = 1
	--     profile.NewField = nil
	--     return profile
	-- end,
}

-- Migrate a profile to the current schema version
function ProfileMigration.Migrate(profile: Profile): Profile
	local currentVersion = profile.SchemaVersion or 0
	local targetVersion = ProfileMigration.CURRENT_SCHEMA

	-- If already at target version, no migration needed
	if currentVersion == targetVersion then
		return profile
	end

	-- Clone the profile to avoid modifying the original
	local migratedProfile = table.clone(profile)

	-- Perform forward migrations
	if currentVersion < targetVersion then
		for version = currentVersion + 1, targetVersion do
			local migrationFunc = ProfileMigration.Migrations[version]
			if migrationFunc then
				migratedProfile = migrationFunc(migratedProfile)
			else
				warn("No migration function found for schema version " .. version)
				migratedProfile.SchemaVersion = version
			end
		end
	-- Perform rollbacks
	elseif currentVersion > targetVersion then
		for version = currentVersion, targetVersion + 1, -1 do
			local rollbackFunc = ProfileMigration.Rollbacks[version]
			if rollbackFunc then
				migratedProfile = rollbackFunc(migratedProfile)
			else
				warn("No rollback function found for schema version " .. version)
				migratedProfile.SchemaVersion = version - 1
			end
		end
	end

	return migratedProfile
end

-- Validate if a profile is compatible with the current schema
function ProfileMigration.IsCompatible(profile: Profile): boolean
	local profileVersion = profile.SchemaVersion or 0
	return profileVersion <= ProfileMigration.CURRENT_SCHEMA
end

-- Get the schema version of a profile
function ProfileMigration.GetSchemaVersion(profile: Profile): number
	return profile.SchemaVersion or 0
end

return ProfileMigration
