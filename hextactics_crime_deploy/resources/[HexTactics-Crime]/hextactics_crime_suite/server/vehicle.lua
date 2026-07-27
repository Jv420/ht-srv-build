local function getVehicle(source, netId, maxDistance)
    netId = tonumber(netId)
    if not netId or netId < 1 then return nil, nil, 'Ongeldig voertuig.' end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return nil, nil, 'Voertuig bestaat niet.' end
    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then return nil, nil, 'Speler niet beschikbaar.' end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (tonumber(maxDistance) or 7.0) then return nil, nil, 'Je staat te ver weg.' end
    return vehicle, HTCrime.NormalizePlate(GetVehicleNumberPlateText(vehicle))
end

local function isOwnedVehicle(plate)
    if not plate then return false end
    return MySQL.scalar.await("SELECT 1 FROM `owned_vehicles` WHERE REPLACE(UPPER(`plate`),' ','')=? LIMIT 1", { plate }) ~= nil
end

RegisterNetEvent('htcrime:server:startVehicleAction', function(actionType, netId)
    local source = source
    if HTCrime.Limited(source, 'vehicleAction', 1000) then return end
    if actionType ~= 'hotwire' and actionType ~= 'plateclone' and actionType ~= 'trackerremove' and actionType ~= 'ecu' then return end
    local vehicle, plate, errorMessage = getVehicle(source, netId, 7.0)
    if not vehicle then return HTCrime.Notify(source, errorMessage, 'error') end
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer or HTCrime.IsPolice(xPlayer) then return end

    local required, duration, minPolice, heat, rep = {}, 20, 1, 8, 3
    if actionType == 'hotwire' then
        if isOwnedVehicle(plate) then return HTCrime.Notify(source, 'Spelervoertuigen moeten via een geldig boost- of omkatcontract worden gestolen.', 'error') end
        required = { lockpick=1 }
        duration = tonumber(Config.vehicleCrime.hotwireDuration) or 24
        minPolice = tonumber(Config.vehicleCrime.hotwireMinPolice) or 1
    elseif actionType == 'plateclone' then
        required = { plate_press=1, plate_blank=1 }
        duration = tonumber(Config.vehicleCrime.plateCloneDuration) or 30
        minPolice, heat, rep = 2, 15, 8
    elseif actionType == 'trackerremove' then
        required = { tracker_scrambler=1 }
        duration = tonumber(Config.vehicleCrime.trackerRemoveDuration) or 25
        minPolice, heat, rep = 1, 10, 5
    elseif actionType == 'ecu' then
        if isOwnedVehicle(plate) then return HTCrime.Notify(source, 'Dit onderdeel kan niet zonder boostcontract uit een spelervoertuig worden gehaald.', 'error') end
        required = { advanced_lockpick=1 }
        duration, minPolice, heat, rep = 32, 1, 12, 6
    end

    if HTCrime.PoliceCount() < minPolice then return HTCrime.Notify(source, ('Minimaal %d politie nodig.'):format(minPolice), 'error') end
    local hasItems, missing = HTCrime.HasItems(source, required)
    if not hasItems then return HTCrime.Notify(source, ('Je mist: %s.'):format(missing), 'error') end
    local coords = GetEntityCoords(vehicle)
    local location = { x=coords.x, y=coords.y, z=coords.z }
    local token = HTCrime.CreateSession(source, {
        actionType=('vehicle_%s'):format(actionType), vehicleAction=actionType, netId=netId, plate=plate,
        location=location, duration=duration, required=required, heat=heat, rep=rep
    })
    HTCrime.Dispatch(source, 'HT-VEH', ('Verdachte voertuigactiviteit: %s'):format(actionType), location, 2)
    HTCrime.LeaveEvidence(source, ('vehicle_%s'):format(actionType), location, { plate=plate })
    TriggerClientEvent('htcrime:client:actionStarted', source, { token=token, actionType=('vehicle_%s'):format(actionType), label=actionType, duration=duration, location=location })
end)

RegisterNetEvent('htcrime:server:completeVehicleAction', function(token)
    local source = source
    if HTCrime.Limited(source, 'completeVehicle', 600) then return end
    local session, errorMessage = HTCrime.GetSession(source, token)
    if not session or not session.vehicleAction then return HTCrime.Notify(source, errorMessage or 'Ongeldige voertuigsessie.', 'error') end
    local vehicle, plate = getVehicle(source, session.netId, 8.0)
    if not vehicle or plate ~= session.plate then HTCrime.EndSession(token) return HTCrime.Notify(source, 'Voertuigcontrole mislukt.', 'error') end
    if os.time() - session.startedAt + 1 < session.duration then HTCrime.EndSession(token) return HTCrime.Notify(source, 'Actie te snel afgerond.', 'error') end
    local hasItems, missing = HTCrime.HasItems(source, session.required)
    if not hasItems then HTCrime.EndSession(token) return HTCrime.Notify(source, ('Je mist: %s.'):format(missing), 'error') end

    local result = {}
    if session.vehicleAction == 'hotwire' then
        if math.random(1, 100) <= 35 then HTCrime.RemoveItem(source, 'lockpick', 1) end
        Entity(vehicle).state:set('htCrimeStolen', true, true)
        Entity(vehicle).state:set('htLocked', false, true)
        SetVehicleDoorsLocked(vehicle, 1)
        result.unlocked = true
    elseif session.vehicleAction == 'plateclone' then
        if not HTCrime.RemoveItem(source, 'plate_blank', 1) then HTCrime.EndSession(token) return end
        local donor = MySQL.single.await('SELECT `plate`,`vin`,`vehicle_model` FROM `ht_vehicle_registry` WHERE `plate`<>? AND `vehicle_model` IS NOT NULL ORDER BY RAND() LIMIT 1', { plate })
        if not donor then HTCrime.AddItem(source, 'plate_blank', 1) HTCrime.EndSession(token) return HTCrime.Notify(source, 'Geen geschikt donorkenteken gevonden.', 'error') end
        local donorPlate = HTCrime.NormalizePlate(donor.plate)
        MySQL.prepare.await([[
            INSERT INTO `ht_crime_cloned_plates` (`original_plate`,`cloned_plate`,`identifier`,`expires_at`)
            VALUES (?,?,?,DATE_ADD(NOW(),INTERVAL 6 HOUR))
            ON DUPLICATE KEY UPDATE `cloned_plate`=VALUES(`cloned_plate`),`identifier`=VALUES(`identifier`),`expires_at`=VALUES(`expires_at`)
        ]], { plate, donorPlate, HTCrime.Identifier(HTCrime.GetPlayer(source)) })
        Entity(vehicle).state:set('htOriginalPlate', plate, true)
        Entity(vehicle).state:set('htClonedPlate', donorPlate, true)
        result.newPlate = donorPlate
    elseif session.vehicleAction == 'trackerremove' then
        local affected = MySQL.update.await('UPDATE `ht_vehicle_registry` SET `tracker_enabled`=0,`updated_at`=NOW() WHERE `plate`=?', { plate })
        Entity(vehicle).state:set('htTrackerDisabled', true, true)
        result.trackerRemoved = (tonumber(affected) or 0) > 0
    elseif session.vehicleAction == 'ecu' then
        if math.random(1, 100) <= 25 then HTCrime.RemoveItem(source, 'advanced_lockpick', 1) end
        if not HTCrime.AddItem(source, 'vehicle_ecu', 1, { plate=plate, stolen=true }) then HTCrime.EndSession(token) return HTCrime.Notify(source, 'Je inventaris is vol.', 'error') end
        result.item = 'vehicle_ecu'
    end

    HTCrime.ChangeProfile(HTCrime.Identifier(HTCrime.GetPlayer(source)), session.rep or 0, session.heat or 0)
    HTCrime.LeaveEvidence(source, session.actionType, session.location, { plate=plate, completed=true }, 55)
    HTCrime.Audit(source, session.actionType, 'completed', result)
    HTCrime.EndSession(token)
    TriggerClientEvent('htcrime:client:vehicleResult', source, session.netId, result)
    TriggerClientEvent('htcrime:client:actionFinished', source)
    HTCrime.Notify(source, 'Voertuigactie voltooid.', 'success')
end)

RegisterNetEvent('htcrime:server:requestBoost', function()
    local source = source
    if HTCrime.Limited(source, 'boostRequest', 2000) then return end
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer or HTCrime.IsPolice(xPlayer) then return end
    if HTCrime.InventoryCount(source, 'burner_phone') < 1 then return HTCrime.Notify(source, 'Je hebt een wegwerptelefoon nodig.', 'error') end
    if HTCrime.BoostContracts[source] then return HTCrime.Notify(source, 'Je hebt al een actief boostcontract.', 'error') end
    local profile = HTCrime.Profile(HTCrime.Identifier(xPlayer))
    if tonumber(profile.reputation) < 10 then return HTCrime.Notify(source, 'Je reputatie is te laag voor voertuigcontracten.', 'error') end
    local model = Config.vehicleCrime.boostModels[math.random(1, #Config.vehicleCrime.boostModels)]
    local delivery = HTCrime.RandomLocation('boost_delivery')
    local contract = { model=model, delivery=delivery, expiresAt=os.time()+1800, reward=math.random(Config.vehicleCrime.boostReward.min, Config.vehicleCrime.boostReward.max) }
    HTCrime.BoostContracts[source] = contract
    TriggerClientEvent('htcrime:client:boostContract', source, contract)
    HTCrime.Notify(source, ('Boostcontract: zoek een %s en lever hem af.'):format(model), 'success')
end)

RegisterNetEvent('htcrime:server:deliverBoost', function(netId)
    local source = source
    if HTCrime.Limited(source, 'boostDelivery', 1200) then return end
    local contract = HTCrime.BoostContracts[source]
    if not contract or os.time() > contract.expiresAt then HTCrime.BoostContracts[source]=nil return HTCrime.Notify(source, 'Geen geldig boostcontract.', 'error') end
    local vehicle, plate = getVehicle(source, netId, 12.0)
    if not vehicle or not HTCrime.Near(source, contract.delivery, 12.0) then return HTCrime.Notify(source, 'Voertuig staat niet op het afleverpunt.', 'error') end
    local requestedHash = GetHashKey(contract.model)
    if GetEntityModel(vehicle) ~= requestedHash then return HTCrime.Notify(source, 'Dit is niet het gevraagde voertuigmodel.', 'error') end
    local xPlayer = HTCrime.GetPlayer(source)
    HTCrime.AddCash(xPlayer, contract.reward, 'Boostcontract')
    HTCrime.ChangeProfile(HTCrime.Identifier(xPlayer), 12, 15)
    HTCrime.LeaveEvidence(source, 'boost_delivery', contract.delivery, { plate=plate, model=contract.model }, 45)
    HTCrime.Audit(source, 'boost_delivery', 'completed', { plate=plate, model=contract.model, reward=contract.reward })
    HTCrime.BoostContracts[source] = nil
    DeleteEntity(vehicle)
    HTCrime.Notify(source, ('Boostcontract voltooid: €%d.'):format(contract.reward), 'success')
    TriggerClientEvent('htcrime:client:boostContract', source, nil)
end)
