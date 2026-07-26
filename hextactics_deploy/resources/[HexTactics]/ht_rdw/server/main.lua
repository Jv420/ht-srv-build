local ESX = exports['es_extended']:getSharedObject()
local Config = json.decode(LoadResourceFile(GetCurrentResourceName(), 'config.json') or '{}')
local rateLimits, roadChecks = {}, {}

local function normalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:upper():gsub('%s+', '')
    if #plate < 1 or #plate > 12 or not plate:match('^[A-Z0-9%-]+$') then return nil end
    return plate
end
local function identifier(xPlayer) return xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier end
local function playerName(xPlayer) return xPlayer.getName and xPlayer.getName() or xPlayer.name or 'Onbekend' end
local function notify(source, message, kind) TriggerClientEvent('ht_rdw:client:notify', source, tostring(message), kind or 'info') end
local function limited(source, key)
    local now = GetGameTimer(); rateLimits[source] = rateLimits[source] or {}
    if now < (rateLimits[source][key] or 0) then return true end
    rateLimits[source][key] = now + math.max(500, tonumber(Config.rateLimitMs) or 1200); return false
end
local function staff(xPlayer)
    if not xPlayer or not xPlayer.job then return false end
    for _, job in ipairs(Config.staffJobs or {}) do if xPlayer.job.name == job then return true end end
    return false
end
local function nearRdw(source)
    local ped = GetPlayerPed(source); if ped == 0 then return false end
    local l = Config.location
    return #(GetEntityCoords(ped) - vector3(l.x, l.y, l.z)) <= (tonumber(Config.interactDistance) or 3.0) + 3.0
end
local function getVehicle(source, netId, maximumDistance)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return nil, nil end
    local ped = GetPlayerPed(source); if ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (maximumDistance or tonumber(Config.vehicleDistance) or 8.0) then return nil, nil end
    return vehicle, normalizePlate(GetVehicleNumberPlateText(vehicle))
end
local function accountBalance(xPlayer, account)
    if account == 'money' then return xPlayer.getMoney() end
    local data = xPlayer.getAccount(account); return data and data.money or 0
end
local function removeMoney(xPlayer, account, amount, reason)
    if account == 'money' then xPlayer.removeMoney(amount, reason) else xPlayer.removeAccountMoney(account, amount, reason) end
end
local function validUntil(value) return value and os.time() < (os.time({ year=tonumber(value:sub(1,4)), month=tonumber(value:sub(6,7)), day=tonumber(value:sub(9,10)), hour=23 })) end
local function publicRecord(plate)
    plate = normalizePlate(plate); if not plate then return nil end
    local row = MySQL.single.await([[SELECT `plate`,`vin`,`registered_name`,`vehicle_model`,`tracker_enabled`,`apk_expires_at`,`insurance_expires_at`,`tax_expires_at`,`stolen_status`,`registration_status` FROM `ht_vehicle_registry` WHERE `plate`=? LIMIT 1]], { plate })
    if not row then return nil end
    return { plate=row.plate, vin=row.vin, registeredName=row.registered_name, model=row.vehicle_model, tracker=tonumber(row.tracker_enabled)==1, apkValid=validUntil(row.apk_expires_at), insuranceValid=validUntil(row.insurance_expires_at), taxValid=validUntil(row.tax_expires_at), stolen=tonumber(row.stolen_status)==1, status=row.registration_status }
end
local function menuData(source, plate)
    local xPlayer = ESX.GetPlayerFromId(source); if not xPlayer then return {} end
    local record = plate and MySQL.single.await([[SELECT *, (`apk_expires_at` > NOW()) AS apk_valid, (`insurance_expires_at` > NOW()) AS insurance_valid FROM `ht_vehicle_registry` WHERE `plate`=? LIMIT 1]], { plate }) or nil
    local fines = MySQL.query.await('SELECT `id`,`plate`,`fine_type`,`amount`,`issued_at` FROM `ht_vehicle_fines` WHERE `offender_identifier`=? AND `status`="open" ORDER BY `issued_at` DESC LIMIT 30', { identifier(xPlayer) }) or {}
    return { registry=record, fines=fines, isStaff=staff(xPlayer) }
end
local function sendMenu(source, plate) TriggerClientEvent('ht_rdw:client:menuData', source, menuData(source, plate)) end

RegisterNetEvent('ht_rdw:server:requestMenu', function(netId)
    local source=source; if limited(source,'menu') or not nearRdw(source) then return end
    local _,plate=getVehicle(source,netId); sendMenu(source,plate)
end)
RegisterNetEvent('ht_rdw:server:inspect', function(netId)
    local source=source; if limited(source,'inspect') or not nearRdw(source) then return end
    local _,plate=getVehicle(source,netId); if not plate then return notify(source,'Geen voertuig dichtbij.','error') end; sendMenu(source,plate)
end)
RegisterNetEvent('ht_rdw:server:insurance', function(netId)
    local source=source; if limited(source,'insurance') or not nearRdw(source) then return end
    local xPlayer=ESX.GetPlayerFromId(source); local _,plate=getVehicle(source,netId); if not xPlayer or not plate then return end
    local row=MySQL.single.await('SELECT `owner` FROM `ht_vehicle_registry` WHERE `plate`=? LIMIT 1',{plate}); if not row or row.owner~=identifier(xPlayer) then return notify(source,'Alleen de eigenaar kan dit voertuig verzekeren.','error') end
    local price=math.max(0,math.floor(tonumber(Config.insurancePrice) or 900)); local account=tostring(Config.moneyAccount or 'bank')
    if accountBalance(xPlayer,account)<price then return notify(source,('Onvoldoende saldo; benodigd €%d.'):format(price),'error') end
    removeMoney(xPlayer,account,price,'Voertuigverzekering'); MySQL.update.await('UPDATE `ht_vehicle_registry` SET `insurance_expires_at`=DATE_ADD(NOW(), INTERVAL ? DAY) WHERE `plate`=?',{math.max(1,tonumber(Config.insuranceValidityDays) or 30),plate}); notify(source,('Verzekering voor %s geactiveerd.'):format(plate),'success'); sendMenu(source,plate)
end)
RegisterNetEvent('ht_rdw:server:apk', function(netId)
    local source=source; if limited(source,'apk') or not nearRdw(source) then return end
    local xPlayer=ESX.GetPlayerFromId(source); if not xPlayer or (Config.apkRequiresStaff and not staff(xPlayer)) then return notify(source,'Je bent geen bevoegde keurmeester.','error') end
    local vehicle,plate=getVehicle(source,netId); if not vehicle or not plate then return notify(source,'Geen geldig voertuig op de keurplaats.','error') end
    local thresholds=Config.inspectionThresholds or {}; local engine=GetVehicleEngineHealth(vehicle); local body=GetVehicleBodyHealth(vehicle); local tank=GetVehiclePetrolTankHealth(vehicle)
    local passed=engine>=tonumber(thresholds.engineHealth or 650) and body>=tonumber(thresholds.bodyHealth or 650) and tank>=tonumber(thresholds.tankHealth or 650)
    MySQL.insert.await('INSERT INTO `ht_vehicle_inspections` (`plate`,`inspector_identifier`,`result`,`engine_health`,`body_health`,`tank_health`) VALUES (?,?,?,?,?,?)',{plate,identifier(xPlayer),passed and 'passed' or 'failed',engine,body,tank})
    if passed then MySQL.update.await('UPDATE `ht_vehicle_registry` SET `apk_expires_at`=DATE_ADD(NOW(), INTERVAL ? MONTH) WHERE `plate`=?',{math.max(1,tonumber(Config.apkValidityMonths) or 12),plate}) end
    notify(source,passed and ('%s is APK-goedgekeurd.'):format(plate) or ('%s is APK-afgekeurd.'):format(plate),passed and 'success' or 'error'); sendMenu(source,plate)
end)
RegisterNetEvent('ht_rdw:server:registerTarget', function(netId,targetId)
    local source=source; if limited(source,'register') or not nearRdw(source) then return end
    local xPlayer=ESX.GetPlayerFromId(source); local target=ESX.GetPlayerFromId(tonumber(targetId)); if not staff(xPlayer) or not target then return notify(source,'Ongeldige RDW-medewerker of ontvanger.','error') end
    local _,plate=getVehicle(source,netId); if not plate then return end
    local pedA,pedB=GetPlayerPed(source),GetPlayerPed(tonumber(targetId)); if pedA==0 or pedB==0 or #(GetEntityCoords(pedA)-GetEntityCoords(pedB))>5.0 then return notify(source,'De nieuwe eigenaar staat te ver weg.','error') end
    local targetIdentifier=identifier(target); MySQL.update.await('UPDATE `ht_vehicle_registry` SET `owner`=?,`registered_name`=?,`updated_at`=NOW() WHERE `plate`=?',{targetIdentifier,playerName(target),plate}); MySQL.prepare.await([[INSERT INTO `ht_vehicle_keys` (`plate`,`identifier`,`key_type`,`active`) VALUES (?,?,'owner',1) ON DUPLICATE KEY UPDATE `active`=1,`key_type`='owner',`revoked_at`=NULL]],{plate,targetIdentifier}); notify(source,('Voertuig %s staat op naam van %s.'):format(plate,playerName(target)),'success'); notify(tonumber(targetId),('Voertuig %s is op jouw naam gezet.'):format(plate),'success'); sendMenu(source,plate)
end)
RegisterNetEvent('ht_rdw:server:payFine', function(fineId)
    local source=source; if limited(source,'fine') then return end
    local xPlayer=ESX.GetPlayerFromId(source); fineId=tonumber(fineId); if not xPlayer or not fineId then return end
    local fine=MySQL.single.await('SELECT `amount` FROM `ht_vehicle_fines` WHERE `id`=? AND `offender_identifier`=? AND `status`="open" LIMIT 1',{fineId,identifier(xPlayer)}); if not fine then return end
    local amount=math.max(0,tonumber(fine.amount) or 0); if accountBalance(xPlayer,'bank')<amount then return notify(source,'Onvoldoende banksaldo.','error') end
    removeMoney(xPlayer,'bank',amount,'RDW-boete'); MySQL.update.await('UPDATE `ht_vehicle_fines` SET `status`="paid",`paid_at`=NOW() WHERE `id`=? AND `status`="open"',{fineId}); notify(source,('Boete van €%d betaald.'):format(amount),'success'); sendMenu(source,nil)
end)
RegisterNetEvent('ht_rdw:server:roadCheck', function(netId)
    local source=source; local xPlayer=ESX.GetPlayerFromId(source); local vehicle,plate=getVehicle(source,netId,6.0); if not xPlayer or not vehicle or not plate then return end
    if GetPedInVehicleSeat(vehicle,-1)~=GetPlayerPed(source) then return end
    local key=('%s:%s'):format(source,plate); if os.time() < (roadChecks[key] or 0) then return end; roadChecks[key]=os.time()+math.max(60,(tonumber(Config.fines and Config.fines.cooldownMinutes) or 360)*60)
    local record=publicRecord(plate); if not record then return end
    local fines=Config.fines or {}; local typeName,amount
    if not record.apkValid then typeName,amount='APK verlopen',tonumber(fines.apkExpired) or 750 elseif not record.insuranceValid then typeName,amount='Geen geldige verzekering',tonumber(fines.noInsurance) or 1000 end
    if not typeName then return end
    MySQL.insert.await('INSERT INTO `ht_vehicle_fines` (`offender_identifier`,`plate`,`fine_type`,`amount`) VALUES (?,?,?,?)',{identifier(xPlayer),plate,typeName,amount}); notify(source,('Nieuwe RDW-boete: %s (€%d).'):format(typeName,amount),'error')
end)

exports('GetPublicVehicleRecord', publicRecord)
AddEventHandler('playerDropped',function() rateLimits[source]=nil end)
