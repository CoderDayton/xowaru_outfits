local Telemetry = require(script.Parent.Modules.Telemetry)

local function init()
	Telemetry.Setup({
		storeName = "Telemetry",
		flushEvery = 60,
		keyPrefix = "metrics",
		enabled = true,
	})
	Telemetry.Start()
end

init()