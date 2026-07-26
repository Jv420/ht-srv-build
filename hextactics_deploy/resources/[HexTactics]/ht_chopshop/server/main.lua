local ESX = exports['es_extended']:getSharedObject()
local ox_inventory = exports.ox_inventory

local resourceName = GetCurrentResourceName()
local rawConfig = LoadResourceFile(resourceName, 'config.json')
assert(rawConfig, ('[%s] config.json ontbreekt'):format(resourceName))
local Config = json.decode(rawConfig)

local rateLimits = {}
local busyVehicles = {}

math.randomseed(os.time() + GetGameTimer())

local function validSqlIdentifier(value)
    return type(value) == 'string' and value:match('^[%w_]+$') ~= nil
end

for _, value in pairs(Config.ownedVehicles) do
    assert(validSqlIdentifier(value), ('[%s] Ongeldige SQL-configuratie'):format(resourceName))
end

local columns = Config.ownedVehicles
local ownedTable = columns.table

local function normalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:upper():gsub('%s+', '')
    if #plate < 1 or #plate > 12 or not plate:match('^[A-Z0-9%-]+$') then return nil end
    return plate
end

local function notify(source, message, kind)
    TriggerClientEvent('ht_chopshop:client:notify', source, tostring(message), kind or 'info')
end

local function rateLimited(source, action)
    local now = GetGameTimer()
    rateLimits[source] = rateLimits[source] or {}
    local nextAllowed = rateLimits[source][action] or 0
    if now < nextAllowed then return true end
    rateLimits[source][action] = now + math.max(500, tonumber(Config.rateLimitMs) or 1500)
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

local function isNearGarage(source)
    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then return false end
    local location = Config.location
    return #(GetEntityCoords(ped) - vector3(location.x, location.y, location.z)) <= (tonumber(Config.interactDistance) or 3.0) + 2.0
end

local function getVehicle(source, netId)
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

    local location = Config.location
    if #(GetEntityCoords(vehicle) - vector3(location.x, location.y, location.z)) > (tonumber(Config.vehicleDistance) or 8.0) + 3.0 then
        return nil, nil, 'Zet het voertuig op de werkplaats.'
    end

    local vehicleClass = GetVehicleClass(vehicle)
    for _, blockedClass in ipairs(Config.blockedVehicleClasses or {}) do
        if vehicleClass == tonumber(blockedClass) then
            return nil, nil, 'Dit voertuigtype kan hier niet worden omgekat.'
        end
    end

    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if not plate then return nil, nil, 'Ongeldig kenteken.' end
    return vehicle, plate
end

local function getAccountBalance(xPlayer, account)
    if account == 'money' then return xPlayer.getMoney() end
    local data = xPlayer.getAccount(account)
    return data and data.money or 0
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

local function hasRequiredItems(source)
    for itemName, amount in pairs(Config.requiredItems or {}) do
        if ox_inventory:GetItemCount(source, itemName) < tonumber(amount) then
            return false, itemName
        end
    end
    return true
end

local function removeRequiredItems(source)
    local removed = {}
    for itemName, amount in pairs(Config.requiredItems or {}) do
        amount = tonumber(amount)
        local success = ox_inventory:RemoveItem(source, itemName, amount)
        if not success then
            for _, item in ipairs(removed) do
                ox_inventory:AddItem(source, item.name, item.amount)
            end
            return false
        end
        removed[#removed + 1] = { name = itemName, amount = amount }
    end
    return true, removed
end

local function restoreItems(source, removed)
    for _, item in ipairs(removed or {}) do
        ox_inventory:AddItem(source, item.name, item.amount)
    end
end

local letters = 'ABCDEFGHJKLMNPRSTUVWXYZ'
local vinChars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789'

local function randomChar(chars)
    local index = math.random(1, #chars)
    return chars:sub(index, index)
end

local function randomPlate()
    return ('%02d-%s%s%s-%d'):format(
        math.random(0, 99),
        randomChar(letters),
        randomChar(letters),
        randomChar(letters),
        math.random(0, 9)
    )
end

local function randomVin()
    local output = {}
    for i = 1, 17 do output[i] = randomChar(vinChars) end
    return table.concat(output)
end

local function plateExists(plate)
    if MySQL.scalar.await('SELECT 1 FROM `ht_vehicle_registry` WHERE `plate` = ? LIMIT 1', { plate }) then
        return true
    end

    local query = ("SELECT 1 FROM `%s` WHERE REPLACE(UPPER(`%s`), ' ', '') = ? LIMIT 1")
        :format(ownedTable, columns.plateColumn)
    return MySQL.scalar.await(query, { plate }) ~= nil
end

local function generatePlate()
    for _ = 1, 50 do
        local plate = randomPlate()
        if not plateExists(plate) then return plate end
    end
    return nil
end

local function generateVin()
    for _ = 1, 50 do
        local vin = randomVin()
        if not MySQL.scalar.await('SELECT 1 FROM `ht_vehicle_registry` WHERE `vin` = ? LIMIT 1', { vin }) then
            return vin
        end
    end
    return nil
end

local function sanitizeVehicleProps(props, modelHash, newPlate)
    if type(props) ~= 'table' then props = {} end

    local safe = {
        model = tonumber(modelHash),
        plate = newPlate,
        plateIndex = math.max(0, math.min(5, tonumber(props.plateIndex) or 0)),
        bodyHealth = math.max(0.0, math.min(1000.0, tonumber(props.bodyHealth) or 1000.0)),
        engineHealth = math.max(-4000.0, math.min(1000.0, tonumber(props.engineHealth) or 1000.0)),
        tankHealth = math.max(0.0, math.min(1000.0, tonumber(props.tankHealth) or 1000.0)),
        fuelLevel = math.max(0.0, math.min(100.0, tonumber(props.fuelLevel) or 100.0)),
        dirtLevel = math.max(0.0, math.min(15.0, tonumber(props.dirtLevel) or 0.0)),
        color1 = math.max(0, math.min(160, tonumber(props.color1) or 0)),
        color2 = math.max(0, math.min(160, tonumber(props.color2) or 0)),
        pearlescentColor = math.max(0, math.min(160, tonumber(props.pearlescentColor) or 0)),
        wheelColor = math.max(0, math.min(160, tonumber(props.wheelColor) or 0)),
        wheels = math.max(0, math.min(13, tonumber(props.wheels) or 0)),
        windowTint = math.max(-1, math.min(6, tonumber(props.windowTint) or -1)),
        xenonColor = math.max(-1, math.min(12, tonumber(props.xenonColor) or -1)),
        livery = math.max(-1, math.min(100, tonumber(props.livery) or -1)),
        extras = type(props.extras) == 'table' and props.extras or {},
        neonEnabled = type(props.neonEnabled) == 'table' and props.neonEnabled or { false, false, false, false },
        neonColor = type(props.neonColor) == 'table' and props.neonColor or { 255, 255, 255 },
        tyreSmokeColor = type(props.tyreSmokeColor) == 'table' and props.tyreSmokeColor or { 255, 255, 255 }
    }

    for i = 0, 49 do
        local key = ('mod%s'):format(i)
        local value = tonumber(props[key])
        if value then safe[key] = math.max(-1, math.min(100, value)) end
    end

    for _, key in ipairs({ 'modTurbo', 'modSmokeEnabled', 'modXenon' }) do
        safe[key] = props[key] == true
    end

    return safe
end

local function addDocument(source, plate, vin, model)
    local metadata = {
        label = ('Voertuigpapieren %s'):format(plate),
        plate = plate,
        vin = vin,
        model = tostring(model),
        issued = os.date('%Y-%m-%d')
    }

    if not ox_inventory:CanCarryItem(source, Config.documentItem, 1, metadata) then
        return false
    end

    return ox_inventory:AddItem(source, Config.documentItem, 1, metadata) == true
end

RegisterNetEvent('ht_chopshop:server:reidentity', function(netId, clientProps)
    local source = source
    if rateLimited(source, 'reidentity') or busyVehicles[tonumber(netId)] then return end

    if not isNearGarage(source) then
        return notify(source, 'Je bent niet bij de omkatgarage.', 'error')
    end

    local xPlayer = getXPlayer(source)
    if not xPlayer then return end

    local vehicle, oldPlate, errorMessage = getVehicle(source, netId)
    if not vehicle then return notify(source, errorMessage, 'error') end

    busyVehicles[tonumber(netId)] = true
    local function finish()
        busyVehicles[tonumber(netId)] = nil
    end

    local identifier = getIdentifier(xPlayer)
    local existingQuery = ("SELECT `%s` AS owner, `%s` AS vehicle FROM `%s` WHERE REPLACE(UPPER(`%s`), ' ', '') = ? LIMIT 1")
        :format(columns.ownerColumn, columns.vehicleColumn, ownedTable, columns.plateColumn)
    local existing = MySQL.single.await(existingQuery, { oldPlate })

    if existing and existing.owner ~= identifier and not Config.allowPlayerVehicleTheft then
        finish()
        return notify(source, 'Dit voertuig staat al op naam van een andere speler.', 'error')
    end

    local hasItems, missingItem = hasRequiredItems(source)
    if not hasItems then
        finish()
        return notify(source, ('Benodigd onderdeel ontbreekt: %s.'):format(missingItem), 'error')
    end

    local price = math.max(0, math.floor(tonumber(Config.price) or 0))
    local account = tostring(Config.moneyAccount or 'money')
    if getAccountBalance(xPlayer, account) < price then
        finish()
        return notify(source, ('Je hebt €%s nodig.'):format(price), 'error')
    end

    local newPlate, vin = generatePlate(), generateVin()
    if not newPlate or not vin then
        finish()
        return notify(source, 'Kon geen unieke voertuigidentiteit genereren.', 'error')
    end

    local modelHash = GetEntityModel(vehicle)
    local modelName = tostring(modelHash)
    local safeProps = sanitizeVehicleProps(clientProps, modelHash, newPlate)
    local vehicleJson = json.encode(safeProps)
    if #vehicleJson > 24000 then
        finish()
        return notify(source, 'Voertuiggegevens zijn te groot.', 'error')
    end

    if not ox_inventory:CanCarryItem(source, Config.documentItem, 1, {
        plate = newPlate,
        vin = vin
    }) then
        finish()
        return notify(source, 'Je inventory heeft geen ruimte voor de voertuigpapieren.', 'error')
    end

    local removedOk, removedItems = removeRequiredItems(source)
    if not removedOk then
        finish()
        return notify(source, 'De benodigde onderdelen konden niet worden ingenomen.', 'error')
    end

    removeMoney(xPlayer, account, price, 'Voertuig omkatten')

    local ownerName = getPlayerName(xPlayer)
    local queries = {}

    if existing then
        queries[#queries + 1] = {
            query = ("UPDATE `%s` SET `%s` = ?, `%s` = ?, `%s` = ?, `%s` = 1 WHERE REPLACE(UPPER(`%s`), ' ', '') = ?")
                :format(ownedTable, columns.ownerColumn, columns.plateColumn, columns.vehicleColumn, columns.storedColumn, columns.plateColumn),
            values = { identifier, newPlate, vehicleJson, oldPlate }
        }
    else
        queries[#queries + 1] = {
            query = ("INSERT INTO `%s` (`%s`, `%s`, `%s`, `%s`, `%s`) VALUES (?, ?, ?, 'car', 1)")
                :format(ownedTable, columns.ownerColumn, columns.plateColumn, columns.vehicleColumn, columns.typeColumn, columns.storedColumn),
            values = { identifier, newPlate, vehicleJson }
        }
    end

    local registryExists = MySQL.scalar.await(
        'SELECT 1 FROM `ht_vehicle_registry` WHERE `plate` = ? LIMIT 1',
        { oldPlate }
    )

    if registryExists then
        queries[#queries + 1] = {
            query = [[
                UPDATE `ht_vehicle_registry`
                SET `plate` = ?, `vin` = ?, `owner` = ?, `registered_name` = ?,
                    `vehicle_model` = ?, `tracker_enabled` = 0, `tracker_code` = NULL,
                    `apk_expires_at` = NULL, `insurance_expires_at` = NULL,
                    `updated_at` = NOW()
                WHERE `plate` = ?
            ]],
            values = { newPlate, vin, identifier, ownerName, modelName, oldPlate }
        }
    else
        queries[#queries + 1] = {
            query = [[
                INSERT INTO `ht_vehicle_registry`
                    (`plate`, `vin`, `owner`, `registered_name`, `vehicle_model`, `tracker_enabled`)
                VALUES (?, ?, ?, ?, ?, 0)
            ]],
            values = { newPlate, vin, identifier, ownerName, modelName }
        }
    end

    queries[#queries + 1] = {
        query = 'UPDATE `ht_vehicle_keys` SET `active` = 0, `revoked_at` = NOW() WHERE `plate` = ?',
        values = { oldPlate }
    }
    queries[#queries + 1] = {
        query = [[
            INSERT INTO `ht_vehicle_keys` (`plate`, `identifier`, `key_type`, `active`)
            VALUES (?, ?, 'owner', 1)
            ON DUPLICATE KEY UPDATE `active` = 1, `key_type` = 'owner', `revoked_at` = NULL
        ]],
        values = { newPlate, identifier }
    }
    queries[#queries + 1] = {
        query = 'DELETE FROM `ht_vehicle_documents` WHERE `plate` = ?',
        values = { oldPlate }
    }
    queries[#queries + 1] = {
        query = [[
            INSERT INTO `ht_vehicle_documents`
                (`plate`, `owner`, `document_number`, `status`)
            VALUES (?, ?, ?, 'valid')
        ]],
        values = { newPlate, identifier, ('DOC-%s'):format(vin:sub(-8)) }
    }
    queries[#queries + 1] = {
        query = [[
            INSERT INTO `ht_vehicle_audit`
                (`actor_identifier`, `action`, `old_plate`, `new_plate`, `vin`, `details`)
            VALUES (?, 'reidentity', ?, ?, ?, ?)
        ]],
        values = { identifier, oldPlate, newPlate, vin, json.encode({ price = price, model = modelName }) }
    }

    local success = MySQL.transaction.await(queries)
    if not success then
        addMoney(xPlayer, account, price, 'Terugbetaling mislukte omkatting')
        restoreItems(source, removedItems)
        finish()
        return notify(source, 'De databasewijziging is teruggedraaid.', 'error')
    end

    ox_inventory:UpdateVehicle(oldPlate, newPlate)
    addDocument(source, newPlate, vin, modelName)

    Entity(vehicle).state:set('htLocked', false, true)
    TriggerClientEvent('ht_chopshop:client:reidentityResult', source, tonumber(netId), newPlate, vin)
    notify(source, ('Nieuwe identiteit geplaatst: %s | VIN %s.'):format(newPlate, vin), 'success')
    finish()
end)

RegisterNetEvent('ht_chopshop:server:tracker', function(netId, action)
    local source = source
    if rateLimited(source, 'tracker') or not isNearGarage(source) then return end

    local xPlayer = getXPlayer(source)
    if not xPlayer then return end

    local vehicle, plate, errorMessage = getVehicle(source, netId)
    if not vehicle then return notify(source, errorMessage, 'error') end

    action = tostring(action)
    local identifier = getIdentifier(xPlayer)
    local registry = MySQL.single.await(
        'SELECT `owner`, `tracker_enabled` FROM `ht_vehicle_registry` WHERE `plate` = ? LIMIT 1',
        { plate }
    )

    if not registry then
        return notify(source, 'Dit voertuig staat niet in het register.', 'error')
    end

    if action == 'add' then
        if registry.owner ~= identifier then
            return notify(source, 'Alleen de geregistreerde eigenaar kan een tracker toevoegen.', 'error')
        end
        if tonumber(registry.tracker_enabled) == 1 then
            return notify(source, 'Er zit al een tracker in dit voertuig.', 'error')
        end

        local itemName = Config.tracker.addItem
        if ox_inventory:GetItemCount(source, itemName) < 1 then
            return notify(source, ('Je mist: %s.'):format(itemName), 'error')
        end
        if not ox_inventory:RemoveItem(source, itemName, 1) then return end

        local trackerCode = ('TRK-%06d'):format(math.random(0, 999999))
        MySQL.update.await(
            'UPDATE `ht_vehicle_registry` SET `tracker_enabled` = 1, `tracker_code` = ?, `updated_at` = NOW() WHERE `plate` = ?',
            { trackerCode, plate }
        )
        notify(source, ('Tracker %s toegevoegd aan %s.'):format(trackerCode, plate), 'success')
        return
    end

    if action == 'remove' then
        if tonumber(registry.tracker_enabled) ~= 1 then
            return notify(source, 'Dit voertuig heeft geen actieve tracker.', 'error')
        end

        local itemName = Config.tracker.removeItem
        if ox_inventory:GetItemCount(source, itemName) < 1 then
            return notify(source, ('Je mist: %s.'):format(itemName), 'error')
        end
        if not ox_inventory:RemoveItem(source, itemName, 1) then return end

        MySQL.update.await(
            'UPDATE `ht_vehicle_registry` SET `tracker_enabled` = 0, `tracker_code` = NULL, `updated_at` = NOW() WHERE `plate` = ?',
            { plate }
        )
        notify(source, ('Tracker verwijderd uit %s.'):format(plate), 'success')
    end
end)

AddEventHandler('playerDropped', function()
    rateLimits[source] = nil
end)
