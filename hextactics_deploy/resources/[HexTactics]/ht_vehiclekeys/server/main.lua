local ESX = exports['es_extended']:getSharedObject()
local resourceName = GetCurrentResourceName()
local rawConfig = LoadResourceFile(resourceName, 'config.json')
assert(rawConfig, ('[%s] config.json ontbreekt'):format(resourceName))
local Config = json.decode(rawConfig)
local rateLimits = {}
local function validSqlIdentifier(value) return type(value) == 'string' and value:match('^[%w_]+$') ~= nil end
for _, value in pairs(Config.ownedVehicles) do assert(validSqlIdentifier(value), ('[%s] Ongeldige SQL-configuratie'):format(resourceName)) end
local ownedTable, ownerColumn, plateColumn = Config.ownedVehicles.table, Config.ownedVehicles.ownerColumn, Config.ownedVehicles.plateColumn
local function normalizePlate(plate) if type(plate) ~= 'string' then return nil end plate=plate:upper():gsub('%s+','') if #plate<1 or #plate>12 or not plate:match('^[A-Z0-9%-]+$') then return nil end return plate end
local function rateLimited(source, action) local now=GetGameTimer(); local p=rateLimits[source] or {}; rateLimits[source]=p; local nextAllowed=p[action] or 0; if now<nextAllowed then return true end; p[action]=now+math.max(250,tonumber(Config.rateLimitMs) or 900); return false end
local function notify(source,message,kind) TriggerClientEvent('ht_vehiclekeys:client:notify',source,tostring(message),kind or 'info') end
local function getXPlayer(source) return ESX.GetPlayerFromId(source) end
local function getIdentifier(xPlayer) return xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier end
local function getVehicleForPlayer(source,netId,maxDistance)
    netId=tonumber(netId); if not netId or netId<1 then return nil,nil,'Ongeldig voertuig.' end
    local vehicle=NetworkGetEntityFromNetworkId(netId); if vehicle==0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle)~=2 then return nil,nil,'Voertuig bestaat niet meer.' end
    local ped=GetPlayerPed(source); if ped==0 or not DoesEntityExist(ped) then return nil,nil,'Speler niet beschikbaar.' end
    if #(GetEntityCoords(ped)-GetEntityCoords(vehicle))>(maxDistance or tonumber(Config.maxVehicleDistance) or 7.0) then return nil,nil,'Je staat te ver van het voertuig.' end
    local plate=normalizePlate(GetVehicleNumberPlateText(vehicle)); if not plate then return nil,nil,'Ongeldig kenteken.' end
    return vehicle,plate
end
local function ownsVehicle(identifier,plate)
    local query=("SELECT 1 FROM `%s` WHERE `%s` = ? AND REPLACE(UPPER(`%s`), ' ', '') = ? LIMIT 1"):format(ownedTable,ownerColumn,plateColumn)
    return MySQL.scalar.await(query,{identifier,plate})~=nil
end
local function hasKeyForIdentifier(identifier,plate)
    local hasKey=MySQL.scalar.await('SELECT 1 FROM `ht_vehicle_keys` WHERE `identifier` = ? AND `plate` = ? AND `active` = 1 LIMIT 1',{identifier,plate})
    if hasKey then return true end
    if ownsVehicle(identifier,plate) then
        MySQL.prepare.await([[INSERT INTO `ht_vehicle_keys` (`plate`,`identifier`,`key_type`,`active`) VALUES (?,?,'owner',1) ON DUPLICATE KEY UPDATE `active`=1,`key_type`='owner',`revoked_at`=NULL]],{plate,identifier})
        return true
    end
    return false
end
local function hasKey(source,plate) local xPlayer=getXPlayer(source); plate=normalizePlate(plate); if not xPlayer or not plate then return false end return hasKeyForIdentifier(getIdentifier(xPlayer),plate) end
local function grantKeyToIdentifier(identifier,plate,keyType)
    plate=normalizePlate(plate); if type(identifier)~='string' or not plate then return false end; keyType=keyType=='owner' and 'owner' or 'shared'
    return MySQL.prepare.await([[INSERT INTO `ht_vehicle_keys` (`plate`,`identifier`,`key_type`,`active`) VALUES (?,?,?,1) ON DUPLICATE KEY UPDATE `active`=1,`key_type`=VALUES(`key_type`),`revoked_at`=NULL]],{plate,identifier,keyType})~=nil
end
RegisterNetEvent('ht_vehiclekeys:server:getKeys',function()
    local source=source; if rateLimited(source,'getKeys') then return end; local xPlayer=getXPlayer(source); if not xPlayer then return end
    local rows=MySQL.query.await([[SELECT k.`plate`,k.`key_type`,r.`vehicle_model`,r.`tracker_enabled` FROM `ht_vehicle_keys` k LEFT JOIN `ht_vehicle_registry` r ON r.`plate`=k.`plate` WHERE k.`identifier`=? AND k.`active`=1 ORDER BY k.`created_at` DESC]],{getIdentifier(xPlayer)}) or {}
    TriggerClientEvent('ht_vehiclekeys:client:keys',source,rows)
end)
RegisterNetEvent('ht_vehiclekeys:server:toggleLock',function(netId)
    local source=source; if rateLimited(source,'toggleLock') then return end; local xPlayer=getXPlayer(source); if not xPlayer then return end
    local vehicle,plate,errorMessage=getVehicleForPlayer(source,netId); if not vehicle then return notify(source,errorMessage,'error') end
    if not hasKeyForIdentifier(getIdentifier(xPlayer),plate) then return notify(source,'Je hebt geen geldige sleutel voor dit voertuig.','error') end
    local state=Entity(vehicle).state; local newLocked=state.htLocked~=true; state:set('htLocked',newLocked,true); TriggerClientEvent('ht_vehiclekeys:client:lockResult',source,netId,plate,newLocked)
end)
RegisterNetEvent('ht_vehiclekeys:server:giveKey',function(plate,targetId)
    local source=source; if rateLimited(source,'giveKey') then return end; plate=normalizePlate(plate); targetId=tonumber(targetId)
    if not plate or not targetId or targetId==source then return notify(source,'Ongeldige ontvanger of kenteken.','error') end
    local xPlayer,targetPlayer=getXPlayer(source),getXPlayer(targetId); if not xPlayer or not targetPlayer then return notify(source,'De andere speler is niet online.','error') end
    local sourcePed,targetPed=GetPlayerPed(source),GetPlayerPed(targetId); if sourcePed==0 or targetPed==0 or #(GetEntityCoords(sourcePed)-GetEntityCoords(targetPed))>(tonumber(Config.giveKeyDistance) or 4.0) then return notify(source,'Je staat te ver van de andere speler.','error') end
    local identifier=getIdentifier(xPlayer); local keyType=MySQL.scalar.await('SELECT `key_type` FROM `ht_vehicle_keys` WHERE `identifier`=? AND `plate`=? AND `active`=1 LIMIT 1',{identifier,plate})
    if keyType~='owner' and not ownsVehicle(identifier,plate) then return notify(source,'Alleen de eigenaar kan een sleutel delen.','error') end
    grantKeyToIdentifier(getIdentifier(targetPlayer),plate,'shared'); notify(source,('Sleutel van %s gedeeld met speler %s.'):format(plate,targetId),'success'); notify(targetId,('Je hebt een voertuigsleutel ontvangen voor %s.'):format(plate),'success')
end)
RegisterNetEvent('ht_vehiclekeys:server:trackVehicle',function(plate)
    local source=source; if rateLimited(source,'trackVehicle') then return end; local xPlayer=getXPlayer(source); plate=normalizePlate(plate); if not xPlayer or not plate then return end
    if not hasKeyForIdentifier(getIdentifier(xPlayer),plate) then return notify(source,'Je hebt geen sleutel voor dit voertuig.','error') end
    if tonumber(MySQL.scalar.await('SELECT `tracker_enabled` FROM `ht_vehicle_registry` WHERE `plate`=? LIMIT 1',{plate}))~=1 then return notify(source,'Op dit voertuig zit geen actieve tracker.','error') end
    for _,vehicle in ipairs(GetAllVehicles()) do if DoesEntityExist(vehicle) and normalizePlate(GetVehicleNumberPlateText(vehicle))==plate then local coords=GetEntityCoords(vehicle); return TriggerClientEvent('ht_vehiclekeys:client:tracked',source,plate,{x=coords.x,y=coords.y,z=coords.z}) end end
    notify(source,'Het voertuig is momenteel niet te lokaliseren.','error')
end)
AddEventHandler('playerDropped',function() rateLimits[source]=nil end)
exports('NormalizePlate',normalizePlate)
exports('HasKey',hasKey)
exports('GrantKey',grantKeyToIdentifier)
exports('GrantKeyToSource',function(source,plate,keyType) local xPlayer=getXPlayer(tonumber(source)); if not xPlayer then return false end return grantKeyToIdentifier(getIdentifier(xPlayer),plate,keyType) end)
exports('RevokeKeys',function(plate) plate=normalizePlate(plate); if not plate then return false end MySQL.update.await('UPDATE `ht_vehicle_keys` SET `active`=0,`revoked_at`=NOW() WHERE `plate`=?',{plate}); return true end)
