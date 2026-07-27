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
    'ht_discord',
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
    if state == 'started' then return '^2' end
    if state == 'starting' then return '^3' end
    return '^1'
end

local function checkPrincipalAce(principal, permissions, label)
    if type(IsPrincipalAceAllowed) ~= 'function' then
        print('^3[HexTactics] ACE-controle niet beschikbaar op deze artifactbuild.^7')
        return true
    end

    local valid = true
    for index = 1, #permissions do
        local permission <const> = permissions[index]
        local allowed <const> = IsPrincipalAceAllowed(principal, permission)
        print(('%s%-44s ^7%s'):format(
            allowed and '^2' or '^1',
            ('ACE %s %s'):format(label, permission),
            allowed and 'allow' or 'DENY'
        ))
        valid = valid and allowed
    end

    return valid
end

local function checkEsxAce()
    return checkPrincipalAce('resource.es_extended', {
        'command.add_ace',
        'command.add_principal',
        'command.remove_principal',
        'command.stop',
    }, 'es_extended')
end

local function checkDiscordAce()
    if GetConvar('ht_discord:enabled', 'false') ~= 'true' then
        return true
    end

    if GetResourceState('ht_discord') ~= 'started' then
        print('^1[HexTactics] ht_discord staat aan maar de resource is niet gestart.^7')
        return false
    end

    return checkPrincipalAce('resource.ht_discord', {
        'command.add_principal',
        'command.remove_principal',
    }, 'ht_discord')
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
        if state ~= 'started' then missing[#missing + 1] = resource end
    end

    for index = 1, #optionalResources do
        local resource <const> = optionalResources[index]
        local state <const> = GetResourceState(resource)
        print(('%s%-34s ^7%s (optioneel/eigen asset)'):format(statusColour(state), resource, state))
        if state ~= 'started' then optionalMissing[#optionalMissing + 1] = resource end
    end

    for index = 1, #conflictingResources do
        local resource <const> = conflictingResources[index]
        local state <const> = GetResourceState(resource)
        if state == 'started' or state == 'starting' then
            conflicts[#conflicts + 1] = resource
            print(('^1CONFLICT: %-25s %s^7'):format(resource, state))
        end
    end

    local esxAceValid <const> = checkEsxAce()
    local discordAceValid <const> = checkDiscordAce()
    local passed <const> = #missing == 0 and #conflicts == 0 and esxAceValid and discordAceValid

    if passed then
        print('^2[HexTactics] Verplichte basis-, ACE- en conflictcontrole geslaagd.^7')
    else
        if #missing > 0 then
            print(('^3[HexTactics] Niet gestart: %s^7'):format(table.concat(missing, ', ')))
        end
        if #conflicts > 0 then
            print(('^1[HexTactics] ESX-conflicten actief: %s^7'):format(table.concat(conflicts, ', ')))
        end
        if not esxAceValid then
            print('^1[HexTactics] ESX mist ACE-rechten voor principalbeheer; player load kan hierdoor vastlopen.^7')
        end
        if not discordAceValid then
            print('^1[HexTactics] ht_discord mist ACE-rechten voor veilige sessierollen.^7')
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
    if source > 0 and not IsPlayerAceAllowed(source, 'hextactics.admin') then return end
    runCheck(source)
end, false)

CreateThread(function()
    Wait(20000)
    runCheck(0)
end)
