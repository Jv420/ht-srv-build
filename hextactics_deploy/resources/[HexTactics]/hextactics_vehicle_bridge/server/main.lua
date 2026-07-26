local function normalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:upper():gsub('%s+', '')
    if #plate < 1 or #plate > 12 or not plate:match('^[A-Z0-9%-]+$') then return nil end
    return plate
end

exports('GrantKeyToSource', function(targetSource, plate, keyType)
    targetSource = tonumber(targetSource)
    plate = normalizePlate(plate)
    if not targetSource or targetSource < 1 or not GetPlayerName(targetSource) or not plate then return false end
    if GetResourceState('ht_vehiclekeys') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports['ht_vehiclekeys']:GrantKeyToSource(targetSource, plate, keyType == 'owner' and 'owner' or 'shared')
    end)
    return ok and result == true
end)

exports('GetVehicleRecord', function(plate)
    plate = normalizePlate(plate)
    if not plate or GetResourceState('ht_rdw') ~= 'started' then return nil end
    local ok, result = pcall(function() return exports['ht_rdw']:GetPublicVehicleRecord(plate) end)
    return ok and result or nil
end)

CreateThread(function()
    Wait(5000)
    if GetResourceState('lc_fuel') == 'started' then
        print('^2[hextactics_vehicle_bridge] LC Fuel-koppeling actief.^7')
    else
        print('^3[hextactics_vehicle_bridge] LC Fuel niet gevonden; GTA-brandstofnative wordt als fallback gebruikt.^7')
    end
end)
