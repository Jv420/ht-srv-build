local ESX = exports['es_extended']:getSharedObject()
local ox_inventory = exports.ox_inventory

local resourceName = GetCurrentResourceName()
local rawConfig = LoadResourceFile(resourceName, 'config.json')
assert(rawConfig, ('[%s] config.json ontbreekt'):format(resourceName))
local Config = json.decode(rawConfig)

local rateLimits = {}
local vehicleCatalog = {}

math.randomseed(os.time() + GetGameTimer() + 117)

local function validSqlIdentifier(value)
    return type(value) == 'string' and value:match('^[%w_]+$') ~= nil
end

for _, value in pairs(Config.ownedVehicles) do
    assert(validSqlIdentifier(value), ('[%s] Ongeldige SQL-configuratie'):format(resourceName))
end

for _, vehicle in ipairs(Config.vehicles or {}) do
    if type(vehicle.model) == 'string' and vehicle.model:match('^[%w_]+$') then
        vehicleCatalog[vehicle.model:lower()] = {
            model = vehicle.model:lower(),
            label = tostring(vehicle.label or vehicle.model),
            price = math.max(1, math.floor(tonumber(vehicle.price) or 1))
        }
    end
end

local columns = Config.ownedVehicles

local function notify(source, message, kind)
    TriggerClientEvent('ht_customdealer:client:notify', source, tostring(message), kind or 'info')
end

local function rateLimited(source, action)
    local now = GetGameTimer()
    rateLimits[source] = rateLimits[source] or {}
    local nextAllowed = rateLimits[source][action] or 0
    if now < nextAllowed then return true end
    rateLimits[source][action] = now + math.max(500, tonumber(Config.rateLimitMs) or 1500)
    return false
end

local function getIdentifier(xPlayer)
    return xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier
end

local function getPlayerName(xPlayer)
    if xPlayer.getName then return xPlayer.getName() end
    return xPlayer.name or 'Onbekend'
end

local function isNearDealer(source)
    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then return false end
    local location = Config.location
    return #(GetEntityCoords(ped) - vector3(location.x, location.y, location.z))
        <= (tonumber(Config.interactDistance) or 3.0) + 3.0
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
        :format(columns.table, columns.plateColumn)
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

local function addDocument(source, plate, vin, label, ownerName)
    local metadata = {
        label = ('Voertuigpapieren %s'):format(plate),
        plate = plate,
        vin = vin,
        model = label,
        owner = ownerName,
        issued = os.date('%Y-%m-%d')
    }
    if not ox_inventory:CanCarryItem(source, Config.documentItem, 1, metadata) then return false end
    return ox_inventory:AddItem(source, Config.documentItem, 1, metadata) == true
end

RegisterNetEvent('ht_customdealer:server:purchase', function(modelName)
    local source = source
    if rateLimited(source, 'purchase') then return end

    if not isNearDealer(source) then
        return notify(source, 'Je bent niet bij de autoverkoop.', 'error')
    end

    modelName = type(modelName) == 'string' and modelName:lower() or ''
    local catalogItem = vehicleCatalog[modelName]
    if not catalogItem then
        return notify(source, 'Dit voertuig staat niet in de verkoopcatalogus.', 'error')
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local modelHash = joaat(catalogItem.model)
    if modelHash == 0 then
        return notify(source, 'Ongeldig voertuigmodel.', 'error')
    end

    local plate, vin = generatePlate(), generateVin()
    if not plate or not vin then
        return notify(source, 'Kon geen uniek kenteken of VIN maken.', 'error')
    end

    local ownerName = getPlayerName(xPlayer)
    local metadataProbe = {
        plate = plate,
        vin = vin,
        model = catalogItem.label,
        owner = ownerName
    }
    if not ox_inventory:CanCarryItem(source, Config.documentItem, 1, metadataProbe) then
        return notify(source, 'Je inventory heeft geen ruimte voor de voertuigpapieren.', 'error')
    end

    local account = tostring(Config.moneyAccount or 'bank')
    if getAccountBalance(xPlayer, account) < catalogItem.price then
        return notify(source, ('Onvoldoende saldo. Benodigd: €%s.'):format(catalogItem.price), 'error')
    end

    removeMoney(xPlayer, account, catalogItem.price, ('Aankoop %s'):format(catalogItem.label))

    local props = {
        model = modelHash,
        plate = plate,
        plateIndex = math.max(0, math.min(5, tonumber(Config.plateIndex) or 1)),
        bodyHealth = 1000.0,
        engineHealth = 1000.0,
        tankHealth = 1000.0,
        fuelLevel = 100.0,
        dirtLevel = 0.0,
        color1 = 0,
        color2 = 0
    }
    local vehicleJson = json.encode(props)
    local identifier = getIdentifier(xPlayer)

    local insertOwned = ("INSERT INTO `%s` (`%s`, `%s`, `%s`, `%s`, `%s`) VALUES (?, ?, ?, 'car', 0)")
        :format(
            columns.table,
            columns.ownerColumn,
            columns.plateColumn,
            columns.vehicleColumn,
            columns.typeColumn,
            columns.storedColumn
        )

    local success = MySQL.transaction.await({
        {
            query = insertOwned,
            values = { identifier, plate, vehicleJson }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_registry`
                    (`plate`, `vin`, `owner`, `registered_name`, `vehicle_model`, `tracker_enabled`)
                VALUES (?, ?, ?, ?, ?, 0)
            ]],
            values = { plate, vin, identifier, ownerName, catalogItem.model }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_keys` (`plate`, `identifier`, `key_type`, `active`)
                VALUES (?, ?, 'owner', 1)
            ]],
            values = { plate, identifier }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_documents` (`plate`, `owner`, `document_number`, `status`)
                VALUES (?, ?, ?, 'valid')
            ]],
            values = { plate, identifier, ('DOC-%s'):format(vin:sub(-8)) }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_sales`
                    (`buyer_identifier`, `plate`, `vin`, `vehicle_model`, `price`, `seller`)
                VALUES (?, ?, ?, ?, ?, 'HexTactics Autoverkoop')
            ]],
            values = { identifier, plate, vin, catalogItem.model, catalogItem.price }
        },
        {
            query = [[
                INSERT INTO `ht_vehicle_audit`
                    (`actor_identifier`, `action`, `old_plate`, `new_plate`, `vin`, `details`)
                VALUES (?, 'dealer_purchase', NULL, ?, ?, ?)
            ]],
            values = {
                identifier,
                plate,
                vin,
                json.encode({ model = catalogItem.model, price = catalogItem.price })
            }
        }
    })

    if not success then
        addMoney(xPlayer, account, catalogItem.price, 'Terugbetaling mislukte voertuigaankoop')
        return notify(source, 'De aankoop is teruggedraaid door een databasefout.', 'error')
    end

    addDocument(source, plate, vin, catalogItem.label, ownerName)

    local spawn = Config.spawn
    ESX.OneSync.SpawnVehicle(
        catalogItem.model,
        vector3(spawn.x, spawn.y, spawn.z),
        tonumber(spawn.heading) or 0.0,
        props,
        function(netId)
            if not netId then
                local markStored = ('UPDATE `%s` SET `%s` = 1 WHERE `%s` = ?')
                    :format(columns.table, columns.storedColumn, columns.plateColumn)
                MySQL.update.await(markStored, { plate })
                notify(source, ('Aankoop gelukt. %s staat in je garage, maar kon niet direct spawnen.'):format(plate), 'success')
                return
            end

            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                Entity(vehicle).state:set('htLocked', false, true)
                SetEntityOrphanMode(vehicle, 2)
            end

            TriggerClientEvent('ht_customdealer:client:purchaseResult', source, netId, plate, vin)
            notify(source, ('%s gekocht voor €%s.'):format(catalogItem.label, catalogItem.price), 'success')
        end
    )
end)

AddEventHandler('playerDropped', function()
    rateLimits[source] = nil
end)
