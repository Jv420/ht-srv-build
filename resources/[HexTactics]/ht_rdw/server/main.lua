local ESX = exports['es_extended']:getSharedObject()
local ox_inventory = exports.ox_inventory

local resourceName = GetCurrentResourceName()
local rawConfig = LoadResourceFile(resourceName, 'config.json')
assert(rawConfig, ('[%s] config.json ontbreekt'):format(resourceName))
local Config = json.decode(rawConfig)

local rateLimits = {}
local fineChecks = {}
local pendingTransfers = {}

local function validSqlIdentifier(value)
    return type(value) == 'string' and value:match('^[%w_]+$') ~= nil
end

for _, value in pairs(Config.ownedVehicles) do
    assert(validSqlIdentifier(value), ('[%s] Ongeldige SQL-configuratie'):format(resourceName))
end

local columns = Config.ownedVehicles

math.randomseed(os.time() + GetGameTimer() + 231)

local vinChars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789'

local function randomChar(chars)
    local index = math.random(1, #chars)
    return chars:sub(index, index)
end

local function generateVin()
    for _ = 1, 50 do
        local output = {}
        for i = 1, 17 do output[i] = randomChar(vinChars) end
        local vin = table.concat(output)
        if not MySQL.scalar.await('SELECT 1 FROM `ht_vehicle_registry` WHERE `vin` = ? LIMIT 1', { vin }) then
            return vin
        end
    end
    return nil
end

local function normalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:upper():gsub('%s+', '')
    if #plate < 1 or #plate > 12 or not plate:match('^[A-Z0-9%-]+$') then return nil end
    return plate
end

local function notify(source, message, kind)
    TriggerClientEvent('ht_rdw:client:notify', source, tostring(message), kind or 'info')
end

local function rateLimited(source, action)
    local now = GetGameTimer()
    rateLimits[source] = rateLimits[source] or {}
    local nextAllowed = rateLimits[source][action] or 0
    if now < nextAllowed then return true end
    rateLimits[source][action] = now + math.max(500, tonumber(Config.rateLimitMs) or 1200)
    return false
end

local function getXPlayer(source)
    return ESX.GetPlayerFromId(source)
end

local function getIdentifier(xPlayer)
    return xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier
end

local function getPlayerName(xPlayer)
    if xPlayer.getName then return xPlayer.getName() end
    return xPlayer.name or 'Onbekend'
end

local function hasStaffJob(xPlayer)
    local job = xPlayer.getJob and xPlayer.getJob() or xPlayer.job
    if not job then return false end
    for _, jobName in ipairs(Config.staffJobs or {}) do
        if job.name == jobName then return true end
    end
    return false
end

local function isNearRdw(source, extra)
    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then return false end
    local location = Config.location
    return #(GetEntityCoords(ped) - vector3(location.x, location.y, location.z))
        <= (tonumber(Config.interactDistance) or 3.0) + (extra or 2.0)
end

local function getVehicle(source, netId, requireRdw)
    netId = tonumber(netId)
    if not netId or netId < 1 then return nil, nil, 'Ongeldig voertuig.' end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        return nil, nil, 'Voertuig bestaat niet meer.'
    end

    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then
        return nil, nil, 'Speler niet beschikbaar.'
    end

    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (tonumber(Config.vehicleDistance) or 8.0) then
        return nil, nil, 'Het voertuig staat te ver weg.'
    end

    if requireRdw then
        local location = Config.location
        if #(GetEntityCoords(vehicle) - vector3(location.x, location.y, location.z))
            > (tonumber(Config.vehicleDistance) or 8.0) + 3.0 then
            return nil, nil, 'Zet het voertuig op de RDW-keuringsplaats.'
        end
    end

    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if not plate then return nil, nil, 'Ongeldig kenteken.' end
    return vehicle, plate
end

local function getAccountBalance(xPlayer, account)
    if account == 'money' then return xPlayer.getMoney() end
    local accountData = xPlayer.getAccount(account)
    return accountData and accountData.money or 0
end

local function removeMoney(xPlayer, account, amount, reason)
    if account == 'money' then
        xPlayer.removeMoney(amount, reason)
    else
        xPlayer.removeAccountMoney(account, amount, reason)
    end
end

local function addMoney(xPlayer, account, amount, reason)
    if account == 'money' then
        xPlayer.addMoney(amount, reason)
    else
        xPlayer.addAccountMoney(account, amount, reason)
    end
end

local function chargePlayer(xPlayer, amount, reason)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local account = tostring(Config.moneyAccount or 'bank')
    if getAccountBalance(xPlayer, account) < amount then return false end
    removeMoney(xPlayer, account, amount, reason)
    return true
end

local function getRegistry(plate)
    return MySQL.single.await([[
        SELECT `plate`, `vin`, `owner`, `registered_name`, `vehicle_model`,
               `tracker_enabled`, `tracker_code`, `apk_expires_at`, `insurance_expires_at`,
               `enforcement_status`,
               (`apk_expires_at` IS NOT NULL AND `apk_expires_at` >= NOW()) AS apk_valid,
               (`insurance_expires_at` IS NOT NULL AND `insurance_expires_at` >= NOW()) AS insurance_valid
        FROM `ht_vehicle_registry`
        WHERE `plate` = ?
        LIMIT 1
    ]], { plate })
end

local function pushMenuData(source, plate)
    local xPlayer = getXPlayer(source)
    if not xPlayer then return end

    local registry = plate and getRegistry(plate) or nil
    local fines = MySQL.query.await([[
        SELECT `id`, `plate`, `fine_type`, `amount`, `issued_at`
        FROM `ht_vehicle_fines`
        WHERE `offender_identifier` = ? AND `status` = 'open'
        ORDER BY `issued_at` DESC
        LIMIT 25
    ]], { getIdentifier(xPlayer) }) or {}

    TriggerClientEvent('ht_rdw:client:menuData', source, {
        registry = registry,
        fines = fines,
        isStaff = hasStaffJob(xPlayer)
    })
end

local function getOnlinePlayerByIdentifier(identifier)
    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if getIdentifier(xPlayer) == identifier then return xPlayer end
    end
    return nil
end

local function playerNearVehicle(xPlayer, vehicle, distance)
    local ped = GetPlayerPed(xPlayer.source)
    if ped == 0 or not DoesEntityExist(ped) then return false end
    return #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= distance
end

local function addDocument(source, registry)
    if not source or not registry then return false end
    local metadata = {
        label = ('Voertuigpapieren %s'):format(registry.plate),
        plate = registry.plate,
        vin = registry.vin,
        owner = registry.registered_name,
        issued = os.date('%Y-%m-%d')
    }
    if not ox_inventory:CanCarryItem(source, Config.documentItem, 1, metadata) then return false end
    return ox_inventory:AddItem(source, Config.documentItem, 1, metadata) == true
end

RegisterNetEvent('ht_rdw:server:requestMenu', function(netId)
    local source = source
    if rateLimited(source, 'requestMenu') or not isNearRdw(source, 3.0) then return end

    local plate
    if tonumber(netId) and tonumber(netId) > 0 then
        local _, foundPlate = getVehicle(source, netId, true)
        plate = foundPlate
    end
    pushMenuData(source, plate)
end)

RegisterNetEvent('ht_rdw:server:inspect', function(netId)
    local source = source
    if rateLimited(source, 'inspect') or not isNearRdw(source, 3.0) then return end

    local vehicle, plate, errorMessage = getVehicle(source, netId, true)
    if not vehicle then return notify(source, errorMessage, 'error') end

    local registry = getRegistry(plate)
    if not registry then
        notify(source, 'Dit voertuig staat niet in het RDW-register.', 'error')
    else
        pushMenuData(source, plate)
    end
end)

RegisterNetEvent('ht_rdw:server:apk', function(netId)
    local source = source
    if rateLimited(source, 'apk') or not isNearRdw(source, 3.0) then return end

    local staff = getXPlayer(source)
    if not staff then return end
    if Config.apkRequiresStaff and not hasStaffJob(staff) then
        return notify(source, 'Alleen RDW-medewerkers kunnen een APK-keuring uitvoeren.', 'error')
    end

    local vehicle, plate, errorMessage = getVehicle(source, netId, true)
    if not vehicle then return notify(source, errorMessage, 'error') end

    local registry = getRegistry(plate)
    if not registry then
        return notify(source, 'Het voertuig moet eerst op naam staan.', 'error')
    end

    local ownerPlayer = getOnlinePlayerByIdentifier(registry.owner)
    if not ownerPlayer or not playerNearVehicle(ownerPlayer, vehicle, 8.0) then
        return notify(source, 'De geregistreerde eigenaar moet bij het voertuig aanwezig zijn.', 'error')
    end

    local thresholds = Config.inspectionThresholds
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)
    local tankHealth = GetVehiclePetrolTankHealth(vehicle)

    local reasons = {}
    if engineHealth < tonumber(thresholds.engineHealth) then reasons[#reasons + 1] = 'motorconditie' end
    if bodyHealth < tonumber(thresholds.bodyHealth) then reasons[#reasons + 1] = 'carrosserie' end
    if tankHealth < tonumber(thresholds.tankHealth) then reasons[#reasons + 1] = 'brandstoftank' end

    if #reasons > 0 then
        MySQL.insert.await([[
            INSERT INTO `ht_vehicle_inspections`
                (`plate`, `inspector_identifier`, `result`, `engine_health`, `body_health`, `tank_health`, `notes`)
            VALUES (?, ?, 'failed', ?, ?, ?, ?)
        ]], {
            plate, getIdentifier(staff), engineHealth, bodyHealth, tankHealth, table.concat(reasons, ', ')
        })
        notify(source, ('APK afgekeurd: %s.'):format(table.concat(reasons, ', ')), 'error')
        if ownerPlayer.source ~= source then
            notify(ownerPlayer.source, ('Je voertuig %s is APK afgekeurd.'):format(plate), 'error')
        end
        return
    end

    local price = math.max(0, math.floor(tonumber(Config.apkPrice) or 0))
    if not chargePlayer(ownerPlayer, price, 'APK-keuring') then
        return notify(source, ('De eigenaar heeft onvoldoende saldo voor €%s.'):format(price), 'error')
    end

    local validity = math.max(1, math.min(60, math.floor(tonumber(Config.apkValidityMonths) or 12)))
    local success = MySQL.transaction.await({
        {
            query = ('UPDATE `ht_vehicle_registry` SET `apk_expires_at` = DATE_ADD(NOW(), INTERVAL %d MONTH), `updated_at` = NOW() WHERE `plate` = ?'):format(validity),
            values = { plate }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_inspections`
                    (`plate`, `inspector_identifier`, `result`, `engine_health`, `body_health`, `tank_health`, `notes`)
                VALUES (?, ?, 'passed', ?, ?, ?, 'Goedgekeurd')
            ]],
            values = { plate, getIdentifier(staff), engineHealth, bodyHealth, tankHealth }
        }
    })

    if not success then
        addMoney(ownerPlayer, tostring(Config.moneyAccount or 'bank'), price, 'Terugbetaling APK')
        return notify(source, 'APK kon niet worden opgeslagen.', 'error')
    end

    notify(source, ('APK goedgekeurd voor %s maanden.'):format(validity), 'success')
    if ownerPlayer.source ~= source then
        notify(ownerPlayer.source, ('Je voertuig %s is APK goedgekeurd.'):format(plate), 'success')
    end
    pushMenuData(source, plate)
end)

RegisterNetEvent('ht_rdw:server:insurance', function(netId)
    local source = source
    if rateLimited(source, 'insurance') or not isNearRdw(source, 3.0) then return end

    local xPlayer = getXPlayer(source)
    if not xPlayer then return end

    local _, plate, errorMessage = getVehicle(source, netId, true)
    if not plate then return notify(source, errorMessage, 'error') end

    local registry = getRegistry(plate)
    if not registry or registry.owner ~= getIdentifier(xPlayer) then
        return notify(source, 'Alleen de geregistreerde eigenaar kan de verzekering afsluiten.', 'error')
    end

    local price = math.max(0, math.floor(tonumber(Config.insurancePrice) or 0))
    if not chargePlayer(xPlayer, price, 'Voertuigverzekering') then
        return notify(source, ('Onvoldoende saldo voor €%s.'):format(price), 'error')
    end

    local days = math.max(1, math.min(3650, math.floor(tonumber(Config.insuranceValidityDays) or 30)))
    local affected = MySQL.update.await(
        ('UPDATE `ht_vehicle_registry` SET `insurance_expires_at` = DATE_ADD(NOW(), INTERVAL %d DAY), `updated_at` = NOW() WHERE `plate` = ? AND `owner` = ?'):format(days),
        { plate, getIdentifier(xPlayer) }
    )

    if not affected or affected < 1 then
        addMoney(xPlayer, tostring(Config.moneyAccount or 'bank'), price, 'Terugbetaling verzekering')
        return notify(source, 'De verzekering kon niet worden opgeslagen.', 'error')
    end

    notify(source, ('Verzekering voor %s is %s dagen geldig.'):format(plate, days), 'success')
    pushMenuData(source, plate)
end)

RegisterNetEvent('ht_rdw:server:registerTarget', function(netId, targetId)
    local source = source
    if rateLimited(source, 'registerTarget') or not isNearRdw(source, 3.0) then return end

    local staff = getXPlayer(source)
    targetId = tonumber(targetId)
    local target = targetId and getXPlayer(targetId)
    if not staff or not hasStaffJob(staff) then
        return notify(source, 'Je bent geen RDW-medewerker.', 'error')
    end
    if not target then
        return notify(source, 'De nieuwe eigenaar is niet online.', 'error')
    end
    if target.source == source then
        return notify(source, 'Gebruik voor je eigen voertuig de normale registratieoptie.', 'error')
    end

    local vehicle, plate, errorMessage = getVehicle(source, netId, true)
    if not vehicle then return notify(source, errorMessage, 'error') end

    if not playerNearVehicle(target, vehicle, 8.0) then
        return notify(source, 'De nieuwe eigenaar moet bij het voertuig staan.', 'error')
    end

    local registry = getRegistry(plate)
    local ownedQuery = ("SELECT `%s` AS owner FROM `%s` WHERE REPLACE(UPPER(`%s`), ' ', '') = ? LIMIT 1")
        :format(columns.ownerColumn, columns.table, columns.plateColumn)
    local ownedVehicle = MySQL.single.await(ownedQuery, { plate })
    if not ownedVehicle then
        return notify(source, 'Dit voertuig staat niet in owned_vehicles en kan niet worden tenaamgesteld.', 'error')
    end

    local currentOwnerIdentifier = registry and registry.owner or ownedVehicle.owner
    local newIdentifier = getIdentifier(target)
    if currentOwnerIdentifier == newIdentifier then
        return notify(source, 'Dit voertuig staat al op naam van deze speler.', 'error')
    end

    local currentOwner = getOnlinePlayerByIdentifier(currentOwnerIdentifier)
    if not currentOwner or not playerNearVehicle(currentOwner, vehicle, 8.0) then
        return notify(source, 'De huidige geregistreerde eigenaar moet online en bij het voertuig staan.', 'error')
    end

    local price = math.max(0, math.floor(tonumber(Config.registrationPrice) or 0))
    local token = ('%s:%s:%06d'):format(source, target.source, math.random(0, 999999))
    pendingTransfers[token] = {
        staffSource = source,
        targetSource = target.source,
        netId = tonumber(netId),
        plate = plate,
        expiresAt = GetGameTimer() + 30000
    }

    TriggerClientEvent('ht_rdw:client:confirmTransfer', target.source, {
        token = token,
        plate = plate,
        price = price,
        staffName = getPlayerName(staff),
        expiresIn = 30
    })
    notify(source, ('Wachten op akkoord van speler %s voor %s.'):format(target.source, plate), 'info')
end)

RegisterNetEvent('ht_rdw:server:respondTransfer', function(token, accepted)
    local source = source
    if rateLimited(source, 'respondTransfer') then return end

    token = tostring(token or '')
    local pending = pendingTransfers[token]
    if not pending or pending.targetSource ~= source then
        return notify(source, 'Deze tenaamstellingsaanvraag is ongeldig of verlopen.', 'error')
    end

    pendingTransfers[token] = nil
    if GetGameTimer() > pending.expiresAt then
        notify(source, 'De tenaamstellingsaanvraag is verlopen.', 'error')
        if GetPlayerName(pending.staffSource) then
            notify(pending.staffSource, 'De tenaamstellingsaanvraag is verlopen.', 'error')
        end
        return
    end

    if accepted ~= true then
        notify(source, 'Je hebt de tenaamstelling geweigerd.', 'info')
        if GetPlayerName(pending.staffSource) then
            notify(pending.staffSource, ('Speler %s heeft de tenaamstelling van %s geweigerd.'):format(source, pending.plate), 'error')
        end
        return
    end

    local staff = getXPlayer(pending.staffSource)
    local target = getXPlayer(source)
    if not staff or not target or not hasStaffJob(staff) or not isNearRdw(pending.staffSource, 3.0) then
        return notify(source, 'De RDW-medewerker is niet meer beschikbaar.', 'error')
    end

    local vehicle, plate, errorMessage = getVehicle(pending.staffSource, pending.netId, true)
    if not vehicle or plate ~= pending.plate then
        notify(source, errorMessage or 'Het voertuig is gewijzigd of niet meer beschikbaar.', 'error')
        return notify(pending.staffSource, errorMessage or 'Het voertuig is gewijzigd of niet meer beschikbaar.', 'error')
    end
    if not playerNearVehicle(target, vehicle, 8.0) then
        return notify(source, 'Je moet bij het voertuig blijven staan.', 'error')
    end

    local registry = getRegistry(plate)
    local ownedQuery = ("SELECT `%s` AS owner FROM `%s` WHERE REPLACE(UPPER(`%s`), ' ', '') = ? LIMIT 1")
        :format(columns.ownerColumn, columns.table, columns.plateColumn)
    local ownedVehicle = MySQL.single.await(ownedQuery, { plate })
    if not ownedVehicle then
        return notify(source, 'Het voertuig staat niet meer in owned_vehicles.', 'error')
    end

    local currentOwnerIdentifier = registry and registry.owner or ownedVehicle.owner
    local currentOwner = getOnlinePlayerByIdentifier(currentOwnerIdentifier)
    if not currentOwner or not playerNearVehicle(currentOwner, vehicle, 8.0) then
        return notify(source, 'De huidige eigenaar is niet meer bij het voertuig.', 'error')
    end

    local newIdentifier = getIdentifier(target)
    if currentOwnerIdentifier == newIdentifier then
        return notify(source, 'Het voertuig staat inmiddels al op jouw naam.', 'error')
    end

    local price = math.max(0, math.floor(tonumber(Config.registrationPrice) or 0))
    if not chargePlayer(target, price, 'Tenaamstelling voertuig') then
        notify(pending.staffSource, ('De nieuwe eigenaar heeft onvoldoende saldo voor €%s.'):format(price), 'error')
        return notify(source, ('Onvoldoende saldo voor de tenaamstelling van €%s.'):format(price), 'error')
    end

    local updateOwned = ("UPDATE `%s` SET `%s` = ? WHERE REPLACE(UPPER(`%s`), ' ', '') = ?")
        :format(columns.table, columns.ownerColumn, columns.plateColumn)

    local vin = registry and registry.vin or generateVin()
    if not vin then
        addMoney(target, tostring(Config.moneyAccount or 'bank'), price, 'Terugbetaling tenaamstelling')
        return notify(source, 'Kon geen uniek VIN genereren.', 'error')
    end

    local queries = {
        { query = updateOwned, values = { newIdentifier, plate } },
        {
            query = 'UPDATE `ht_vehicle_keys` SET `active` = 0, `revoked_at` = NOW() WHERE `plate` = ?',
            values = { plate }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_keys` (`plate`, `identifier`, `key_type`, `active`)
                VALUES (?, ?, 'owner', 1)
                ON DUPLICATE KEY UPDATE `active` = 1, `key_type` = 'owner', `revoked_at` = NULL
            ]],
            values = { plate, newIdentifier }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_documents` (`plate`, `owner`, `document_number`, `status`)
                VALUES (?, ?, ?, 'valid')
                ON DUPLICATE KEY UPDATE `owner` = VALUES(`owner`), `status` = 'valid', `issued_at` = NOW()
            ]],
            values = { plate, newIdentifier, ('DOC-%s'):format(vin:sub(-8)) }
        }
    }

    if registry then
        queries[#queries + 1] = {
            query = 'UPDATE `ht_vehicle_registry` SET `owner` = ?, `registered_name` = ?, `updated_at` = NOW() WHERE `plate` = ?',
            values = { newIdentifier, getPlayerName(target), plate }
        }
    else
        queries[#queries + 1] = {
            query = [[
                INSERT INTO `ht_vehicle_registry`
                    (`plate`, `vin`, `owner`, `registered_name`, `vehicle_model`, `tracker_enabled`)
                VALUES (?, ?, ?, ?, ?, 0)
            ]],
            values = { plate, vin, newIdentifier, getPlayerName(target), tostring(GetEntityModel(vehicle)) }
        }
    end

    queries[#queries + 1] = {
        query = [[
            INSERT INTO `ht_vehicle_audit`
                (`actor_identifier`, `action`, `old_plate`, `new_plate`, `vin`, `details`)
            VALUES (?, ?, ?, ?, ?, ?)
        ]],
        values = {
            getIdentifier(staff),
            registry and 'registration_transfer' or 'first_registration',
            plate,
            plate,
            vin,
            json.encode({ from = currentOwnerIdentifier, to = newIdentifier, price = price, consent = true })
        }
    }

    local success = MySQL.transaction.await(queries)
    if not success then
        addMoney(target, tostring(Config.moneyAccount or 'bank'), price, 'Terugbetaling tenaamstelling')
        notify(pending.staffSource, 'Tenaamstelling is teruggedraaid.', 'error')
        return notify(source, 'Tenaamstelling is teruggedraaid.', 'error')
    end

    local updatedRegistry = getRegistry(plate)
    if not addDocument(target.source, updatedRegistry) then
        notify(source, 'Tenaamstelling gelukt; maak ruimte vrij en vraag de RDW om een nieuw papieren item.', 'warning')
    end

    notify(pending.staffSource, ('%s staat nu op naam van speler %s.'):format(plate, source), 'success')
    notify(source, ('Voertuig %s staat nu op jouw naam.'):format(plate), 'success')
    pushMenuData(pending.staffSource, plate)
end)

RegisterNetEvent('ht_rdw:server:payFine', function(fineId)
    local source = source
    if rateLimited(source, 'payFine') or not isNearRdw(source, 3.0) then return end

    local xPlayer = getXPlayer(source)
    fineId = tonumber(fineId)
    if not xPlayer or not fineId then return end

    local fine = MySQL.single.await([[
        SELECT `id`, `amount`, `plate`
        FROM `ht_vehicle_fines`
        WHERE `id` = ? AND `offender_identifier` = ? AND `status` = 'open'
        LIMIT 1
    ]], { fineId, getIdentifier(xPlayer) })

    if not fine then return notify(source, 'Boete niet gevonden.', 'error') end
    if not chargePlayer(xPlayer, fine.amount, 'RDW-boete') then
        return notify(source, ('Onvoldoende saldo voor €%s.'):format(fine.amount), 'error')
    end

    local affected = MySQL.update.await(
        [[UPDATE `ht_vehicle_fines` SET `status` = 'paid', `paid_at` = NOW() WHERE `id` = ? AND `status` = 'open']],
        { fineId }
    )
    if not affected or affected < 1 then
        addMoney(xPlayer, tostring(Config.moneyAccount or 'bank'), fine.amount, 'Terugbetaling RDW-boete')
        return notify(source, 'De boete kon niet worden verwerkt.', 'error')
    end

    notify(source, ('Boete voor %s is betaald.'):format(fine.plate), 'success')
    pushMenuData(source, nil)
end)

local function issueFine(source, plate, fineType, amount)
    local xPlayer = getXPlayer(source)
    if not xPlayer then return end

    local identifier = getIdentifier(xPlayer)
    local cooldownMinutes = math.max(1, math.floor(tonumber(Config.fines.cooldownMinutes) or 360))
    local recent = MySQL.scalar.await(
        ('SELECT 1 FROM `ht_vehicle_fines` WHERE `offender_identifier` = ? AND `plate` = ? AND `fine_type` = ? AND `issued_at` >= DATE_SUB(NOW(), INTERVAL %d MINUTE) LIMIT 1'):format(cooldownMinutes),
        { identifier, plate, fineType }
    )
    if recent then return end

    amount = math.max(1, math.floor(tonumber(amount) or 1))
    local status = Config.fines.autoCharge and 'paid' or 'open'
    MySQL.insert.await([[
        INSERT INTO `ht_vehicle_fines`
            (`offender_identifier`, `plate`, `fine_type`, `amount`, `status`, `paid_at`)
        VALUES (?, ?, ?, ?, ?, CASE WHEN ? = 'paid' THEN NOW() ELSE NULL END)
    ]], { identifier, plate, fineType, amount, status, status })

    if Config.fines.autoCharge then
        if getAccountBalance(xPlayer, tostring(Config.moneyAccount or 'bank')) >= amount then
            removeMoney(xPlayer, tostring(Config.moneyAccount or 'bank'), amount, 'Automatische RDW-boete')
            notify(source, ('Automatische boete: €%s voor %s.'):format(amount, fineType), 'error')
        else
            MySQL.update.await(
                [[UPDATE `ht_vehicle_fines` SET `status` = 'open', `paid_at` = NULL WHERE `offender_identifier` = ? AND `plate` = ? AND `fine_type` = ? ORDER BY `id` DESC LIMIT 1]],
                { identifier, plate, fineType }
            )
            notify(source, ('Openstaande boete: €%s voor %s.'):format(amount, fineType), 'error')
        end
    else
        notify(source, ('Openstaande boete: €%s voor %s.'):format(amount, fineType), 'error')
    end
end

RegisterNetEvent('ht_rdw:server:roadCheck', function(netId)
    local source = source
    local now = GetGameTimer()
    local nextAllowed = fineChecks[source] or 0
    if now < nextAllowed then return end
    fineChecks[source] = now + math.max(30000, tonumber(Config.fines.checkIntervalMs) or 60000)

    local vehicle, plate = getVehicle(source, netId, false)
    if not vehicle or not plate then return end

    local ped = GetPlayerPed(source)
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    local registry = getRegistry(plate)
    if not registry then return end

    if tonumber(registry.apk_valid) ~= 1 then
        issueFine(source, plate, 'APK verlopen', Config.fines.apkExpired)
    end
    if tonumber(registry.insurance_valid) ~= 1 then
        issueFine(source, plate, 'Geen geldige verzekering', Config.fines.noInsurance)
    end
end)

AddEventHandler('playerDropped', function()
    local droppedSource = source
    rateLimits[droppedSource] = nil
    fineChecks[droppedSource] = nil

    for token, pending in pairs(pendingTransfers) do
        if pending.staffSource == droppedSource or pending.targetSource == droppedSource then
            local otherSource = pending.staffSource == droppedSource and pending.targetSource or pending.staffSource
            if GetPlayerName(otherSource) then
                notify(otherSource, 'De tenaamstellingsaanvraag is geannuleerd omdat iemand de server verliet.', 'error')
            end
            pendingTransfers[token] = nil
        end
    end
end)

-- Compatibiliteit voor bestaande HexTactics/ESX-resources.
local function identifiersMatch(left, right)
    if GetResourceState('hextactics_core') == 'started' then
        local ok, result = pcall(function()
            return exports['hextactics_core']:IsIdentifierMatch(left, right)
        end)
        if ok then return result == true end
    end
    return tostring(left or '') ~= '' and tostring(left) == tostring(right)
end

local function getRegistrationExport(plate)
    plate = normalizePlate(plate)
    if not plate then return nil end
    local registry = getRegistry(plate)
    if not registry then return nil end

    registry.owner_identifier = registry.owner
    registry.active = 1
    registry.registration_type = 'nl'

    local complianceStatus = (tonumber(registry.apk_valid) == 1 and tonumber(registry.insurance_valid) == 1)
        and 'clear' or 'overdue'
    if registry.enforcement_status ~= 'enforcement' and registry.enforcement_status ~= 'impounded' then
        registry.enforcement_status = complianceStatus
    end

    return registry
end

local function recordInitialRegistration(plate)
    plate = normalizePlate(plate)
    if not plate then return false, 'invalid_plate' end
    if getRegistry(plate) then return true end

    local query = ("SELECT `%s` AS owner, `%s` AS vehicle FROM `%s` WHERE REPLACE(UPPER(`%s`), ' ', '') = ? LIMIT 1")
        :format(columns.ownerColumn, columns.vehicleColumn, columns.table, columns.plateColumn)
    local owned = MySQL.single.await(query, { plate })
    if not owned or type(owned.owner) ~= 'string' then return false, 'not_owned' end

    local vin = generateVin()
    if not vin then return false, 'vin_generation_failed' end

    local vehicleModel = 'unknown'
    if type(owned.vehicle) == 'string' and owned.vehicle ~= '' then
        local ok, props = pcall(json.decode, owned.vehicle)
        if ok and type(props) == 'table' and props.model ~= nil then
            vehicleModel = tostring(props.model)
        end
    end

    local onlineOwner = getOnlinePlayerByIdentifier(owned.owner)
    local registeredName = onlineOwner and getPlayerName(onlineOwner) or owned.owner
    local documentNumber = ('DOC-%s'):format(vin:sub(-8))

    local success = MySQL.transaction.await({
        {
            query = [[
                INSERT INTO `ht_vehicle_registry`
                    (`plate`, `vin`, `owner`, `registered_name`, `vehicle_model`, `tracker_enabled`)
                VALUES (?, ?, ?, ?, ?, 0)
            ]],
            values = { plate, vin, owned.owner, registeredName, vehicleModel }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_keys` (`plate`, `identifier`, `key_type`, `active`)
                VALUES (?, ?, 'owner', 1)
                ON DUPLICATE KEY UPDATE `active` = 1, `key_type` = 'owner', `revoked_at` = NULL
            ]],
            values = { plate, owned.owner }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_documents` (`plate`, `owner`, `document_number`, `status`)
                VALUES (?, ?, ?, 'valid')
                ON DUPLICATE KEY UPDATE `owner` = VALUES(`owner`), `status` = 'valid'
            ]],
            values = { plate, owned.owner, documentNumber }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_audit`
                    (`actor_identifier`, `action`, `old_plate`, `new_plate`, `vin`, `details`)
                VALUES (?, 'compat_initial_registration', ?, ?, ?, ?)
            ]],
            values = { owned.owner, plate, plate, vin, json.encode({ source = 'owned_vehicles' }) }
        }
    })

    return success == true
end

exports('GetRegistrationByPlate', getRegistrationExport)
exports('IsIdentifierMatch', identifiersMatch)
exports('RecordInitialRegistration', recordInitialRegistration)
exports('GetVehicleStatus', function(plate)
    local registry = getRegistrationExport(plate)
    if not registry then return nil end
    return {
        plate = registry.plate,
        vin = registry.vin,
        owner = registry.owner,
        apkValid = tonumber(registry.apk_valid) == 1,
        insuranceValid = tonumber(registry.insurance_valid) == 1,
        trackerEnabled = tonumber(registry.tracker_enabled) == 1
    }
end)

RegisterCommand(tostring(Config.lookupCommand or 'kentekencheck'), function(source, args)
    if source == 0 then
        local registry = getRegistrationExport(args[1])
        print(registry and json.encode(registry) or '[ht_rdw] Kenteken niet gevonden.')
        return
    end

    local xPlayer = getXPlayer(source)
    if not xPlayer or rateLimited(source, 'plateLookup') then return end

    local job = xPlayer.getJob and xPlayer.getJob() or xPlayer.job
    local allowed = false
    for _, jobName in ipairs(Config.lookupJobs or {}) do
        if job and job.name == jobName then allowed = true break end
    end
    if not allowed then return notify(source, 'Je hebt geen toegang tot de kentekenregistratie.', 'error') end

    local registry = getRegistrationExport(args[1])
    if not registry then return notify(source, 'Kenteken niet gevonden.', 'error') end

    notify(source, ('%s | VIN %s | APK %s | verzekering %s | tracker %s'):format(
        registry.plate,
        registry.vin,
        tonumber(registry.apk_valid) == 1 and 'geldig' or 'ongeldig',
        tonumber(registry.insurance_valid) == 1 and 'geldig' or 'ongeldig',
        tonumber(registry.tracker_enabled) == 1 and 'aanwezig' or 'niet aanwezig'
    ), 'info')
end, false)

