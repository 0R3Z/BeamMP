-- Copyright (C) 2024 BeamMP Ltd., BeamMP team and contributors.
-- Licensed under AGPL-3.0 (or later), see <https://www.gnu.org/licenses/>.
-- SPDX-License-Identifier: AGPL-3.0-or-later

local ver = split(beamng_versionb, ".")
local majorVer = tonumber(ver[2])
local compatibleVersion = 31
if majorVer ~= compatibleVersion then
	log('W', 'versionCheck', 'BeamMP is incompatible with BeamNG.drive version '..beamng_versionb)
	log('M', 'versionCheck', 'Deactivating BeamMP mod.')
	core_modmanager.deactivateMod('multiplayerbeammp')
	core_modmanager.deactivateMod('beammp')
	if majorVer > compatibleVersion then
		guihooks.trigger("toastrMsg", {type="error", title="Error loading BeamMP", msg="BeamMP is currently not compatible with BeamNG.drive version "..beamng_versionb..". Check the BeamMP Discord for updates."})
		log('W', 'versionCheck', 'BeamMP is currently not compatible with BeamNG.drive version '..beamng_versionb..'. Check the BeamMP Discord for updates.')
	else
		guihooks.trigger("toastrMsg", {type="error", title="Error loading BeamMP", msg="BeamMP is not compatible with BeamNG.drive version "..beamng_versionb.. ". Please update your game."})
		log('W', 'versionCheck', 'BeamMP is not compatible with BeamNG.drive version '..beamng_versionb.. '. Please update your game.')
	end
	return
else
	log('M', 'versionCheck', 'BeamMP is compatible with the current version.')
end

setExtensionUnloadMode("multiplayer/multiplayer", "manual")
setExtensionUnloadMode("MPDebug", "manual")
setExtensionUnloadMode("MPModManager", "manual")
setExtensionUnloadMode("MPCoreNetwork", "manual")
setExtensionUnloadMode("MPConfig", "manual")
setExtensionUnloadMode("MPGameNetwork", "manual")
setExtensionUnloadMode("MPVehicleGE", "manual")
setExtensionUnloadMode("MPInputsGE", "manual")
setExtensionUnloadMode("MPElectricsGE", "manual")
setExtensionUnloadMode("positionGE", "manual")
setExtensionUnloadMode("MPPowertrainGE", "manual")
setExtensionUnloadMode("MPUpdatesGE", "manual")
setExtensionUnloadMode("nodesGE", "manual")
setExtensionUnloadMode("UI", "manual")

-- load this file last so it can reference the other
setExtensionUnloadMode("MPHelpers", "manual")
