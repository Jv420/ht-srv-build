local requiredResources <const> = {
    'oxmysql',
    'ox_lib',
    'es_extended',
    'esx_identity',
    'skinchanger',
    'esx_skin',
    'esx_multicharacter',
    'ox_inventory',
    'ox_target',
    'hextactics_core',
    'ht_vehiclekeys',
    'ht_chopshop',
    'ht_rdw',
    'ht_customdealer',
    'hextactics_vehicle_bridge',
    'hextactics_npc_roleplay',
}

local optionalResources <const> = {
    'lc_utils',
    'lc_fuel',
    'hextactics_spawn_guard',
    'hextactics_crime_suite',
}

local conflictingResources <const> = {
    'mapmanager',
    'basic-gamemode',
    'fivem-map-skater',
    'ox_fuel',
    'LegacyFuel',
    'esx_inventory',
    'esx_garage',
    'zerodream_parking',
    'idev_keys',
    'p_vehiclekeys',
    'iwa_policejob',
    'ls_usedvehicles',
}

local function statusColour(state)
    if state == 'started' then
        return '^2'
    end

    if state == 'starting' then
        return '^3'
    end

    return '^1'
end

local function checkEsxAce()
    if type(IsPrincipalAceAllowed) ~= 'function' then
        print('^3[HexTactics] ACE-controle niet beschikbaar op deze artifactbuild.^7')
        return true
    end

    local permissions <const> = {
        'command.add_ace',
        'command.add_principal',
        'command.remove_principal',
        'command.stop',
    }

    local valid = true
    for index = 1, #permissions do
        local permission <const> = permissions[index]
        local allowed <const> = IsPrincipalAceAllowed('resource.es_extended', permission)
        print(('%s%-34s ^7%s'):format(allowed and '^2' or '^1', ('ACE es_extended %s'):format(permission), allowed and 'allow' or 'DENY'))
        valid = valid and allowed
    end

    return valid
end

local function runCheck(source)
    local missing = {}
    local conflicts = {}
    local optionalMissing = {}

    print('^5========== HexTactics deploycontrole ==========^7')

    for index = 1, #requiredResources do
        local resource <const> = requiredResources[index]
        local state <const> = GetResourceState(resource)
        print(('%s%-34s ^7%s'):format(statusColour(state), resource, state))

        if state ~= 'started' then
            missing[#missing + 1] = resource
        end
    end

    for index = 1, #optionalResources do
        local resource <const> = optionalResources[index]
        local state <const> = GetResourceState(resource)
        print(('%s%-34s ^7%s (optioneel/eigen asset)'):format(statusColour(state), resource, state))

        if state ~= 'started' then
            optionalMissing[#optionalMissing + 1] = resource
        end
    end

    for index = 1, #conflictingResources do
        local resource <const> = conflictingResources[index]
        local state <const> = GetResourceState(resource)

        if state == 'started' or state == 'starting' then
            conflicts[#conflicts + 1] = resource
            print(('^1CONFLICT: %-25s %s^7'):format(resource, state))
        end
    end

    local aceValid <const> = checkEsxAce()
    local passed <const> = #missing == 0 and #conflicts == 0 and aceValid

    if passed then
        print('^2[HexTactics] Verplichte basis-, ACE- en conflictcontrole geslaagd.^7')
    else
        if #missing > 0 then
            print(('^3[HexTactics] Niet gestart: %s^7'):format(table.concat(missing, ', ')))
        end

        if #conflicts > 0 then
            print(('^1[HexTactics] ESX-conflicten actief: %s^7'):format(table.concat(conflicts, ', ')))
        end

        if not aceValid then
            print('^1[HexTactics] ESX mist ACE-rechten voor principalbeheer; player load kan hierdoor vastlopen.^7')
        end
    end

    if #optionalMissing > 0 then
        print(('^3[HexTactics] Optioneel niet gestart: %s^7'):format(table.concat(optionalMissing, ', ')))
    end

    if source and source > 0 then
        TriggerClientEvent('chat:addMessage', source, {
            args = {
                'HexTactics',
                passed and 'Basis-, ACE- en conflictcontrole geslaagd.' or 'Controle mislukt; bekijk de serverconsole.',
            },
        })
    end
end

RegisterCommand('hextacticscheck', function(source)
    if source > 0 and not IsPlayerAceAllowed(source, 'hextactics.admin') then
        return
    end

    runCheck(source)
end, false)

CreateThread(function()
    Wait(20000)
    runCheck(0)
end)
