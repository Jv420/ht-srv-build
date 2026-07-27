local RESOURCE <const> = GetCurrentResourceName()
local API_BASE <const> = 'https://discord.com/api/v10'

local SETTINGS <const> = {
    enabled = GetConvar('ht_discord:enabled', 'false') == 'true',
    botToken = GetConvar('ht_discord:botToken', ''),
    guildId = GetConvar('ht_discord:guildId', ''),
    inviteUrl = GetConvar('ht_discord:invite', Config.InviteUrl or ''),
}

local roleIdsByKey = {}
local roleKeysById = {}
local channelIdsByKey = {}
local playerSessions = {}
local memberCache = {}
local metadataLoadedAt = 0
local provisioningBusy = false

local VIEW_CHANNEL <const> = 1 << 10
local SEND_MESSAGES <const> = 1 << 11
local READ_MESSAGE_HISTORY <const> = 1 << 16
local CONNECT <const> = 1 << 20
local SPEAK <const> = 1 << 21

local function nowSeconds()
    return os.time()
end

local function trim(value)
    if type(value) ~= 'string' then return '' end
    return value:match('^%s*(.-)%s*$') or ''
end

local function safeText(value, maximum)
    value = tostring(value or '')
    value = value:gsub('[\r\n\t]', ' ')
    return value:sub(1, maximum or 1000)
end

local function apiReady()
    return SETTINGS.enabled and SETTINGS.botToken ~= '' and SETTINGS.guildId:match('^%d+$') ~= nil
end

local function decodeJson(value)
    if type(value) ~= 'string' or value == '' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or nil
end

local function discordRequest(method, path, payload, attempt)
    attempt = attempt or 1

    if not apiReady() then
        return 0, nil, 'Discord is niet volledig geconfigureerd.'
    end

    local body = payload and json.encode(payload) or ''
    local status, responseBody, _, errorData = PerformHttpRequestAwait(
        API_BASE .. path,
        method,
        body,
        {
            ['Authorization'] = 'Bot ' .. SETTINGS.botToken,
            ['Content-Type'] = 'application/json',
            ['User-Agent'] = 'HexTactics-Discord/1.0 (+FiveM)',
        },
        { followLocation = true }
    )

    local decoded = decodeJson(responseBody)

    if status == 429 and attempt < 3 then
        local retryAfter = decoded and tonumber(decoded.retry_after) or 1
        Wait(math.max(250, math.ceil((retryAfter or 1) * 1000)))
        return discordRequest(method, path, payload, attempt + 1)
    end

    if status < 200 or status >= 300 then
        local message = decoded and (decoded.message or decoded.code) or errorData or responseBody or 'onbekende fout'
        return status, decoded, safeText(message, 300)
    end

    return status, decoded, nil
end

local function getIdentifier(source, identifierType)
    local identifiers = GetPlayerIdentifiers(source)
    local prefix = identifierType .. ':'

    for index = 1, #identifiers do
        local identifier = identifiers[index]
        if identifier:sub(1, #prefix) == prefix then
            return identifier
        end
    end

    return nil
end

local function getDiscordId(source)
    local identifier = getIdentifier(source, 'discord')
    return identifier and identifier:match('^discord:(%d+)$') or nil
end

local function getLicensePrincipal(source)
    local identifier = getIdentifier(source, 'license')
    if not identifier or not identifier:match('^license:[%x]+$') then
        return nil
    end

    return 'identifier.' .. identifier
end

local function validPrincipalGroup(group)
    return type(group) == 'string' and group:match('^group%.[%w_.-]+$') ~= nil
end

local function removeSessionPrincipals(source)
    local session = playerSessions[source]
    if not session or not session.principal or type(session.groups) ~= 'table' then return end

    for group in pairs(session.groups) do
        if validPrincipalGroup(group) then
            ExecuteCommand(('remove_principal %s %s'):format(session.principal, group))
        end
    end

    session.groups = {}
end

local function applySessionPrincipals(source, principal, roleKeys)
    removeSessionPrincipals(source)

    local groups = {}
    for _, role in ipairs(Config.Roles or {}) do
        if roleKeys[role.key] and type(role.principalGroups) == 'table' then
            for index = 1, #role.principalGroups do
                local group = role.principalGroups[index]
                if validPrincipalGroup(group) then
                    groups[group] = true
                end
            end
        end
    end

    playerSessions[source] = playerSessions[source] or {}
    playerSessions[source].principal = principal
    playerSessions[source].groups = groups
    playerSessions[source].roles = roleKeys

    for group in pairs(groups) do
        ExecuteCommand(('add_principal %s %s'):format(principal, group))
    end
end

local function roleNamesByExactName(roles)
    local result = {}
    local duplicate = {}

    for _, role in ipairs(roles or {}) do
        if type(role.name) == 'string' and type(role.id) == 'string' then
            if result[role.name] then duplicate[role.name] = true end
            result[role.name] = role
        end
    end

    for name in pairs(duplicate) do
        result[name] = nil
        print(('^1[%s] Dubbele Discord-rolnaam geweigerd: %s^7'):format(RESOURCE, name))
    end

    return result
end

local function rebuildRoleCache(roles)
    roleIdsByKey = {}
    roleKeysById = {}
    local byName = roleNamesByExactName(roles)

    for _, configuredRole in ipairs(Config.Roles or {}) do
        local discordRole = byName[configuredRole.name]
        if discordRole then
            roleIdsByKey[configuredRole.key] = discordRole.id
            roleKeysById[discordRole.id] = configuredRole.key
        end
    end
end

local function rebuildChannelCache(channels)
    channelIdsByKey = {}
    local categoryIdByName = {}

    for _, channel in ipairs(channels or {}) do
        if channel.type == 4 then
            categoryIdByName[channel.name] = channel.id
        end
    end

    for _, category in ipairs(Config.Provisioning.categories or {}) do
        local categoryId = categoryIdByName[category.name]
        if categoryId then
            channelIdsByKey[category.key] = categoryId
            for _, configuredChannel in ipairs(category.channels or {}) do
                for _, channel in ipairs(channels or {}) do
                    if channel.parent_id == categoryId and channel.name == configuredChannel.name then
                        channelIdsByKey[configuredChannel.key] = channel.id
                        break
                    end
                end
            end
        end
    end
end

local function refreshGuildMetadata(force)
    if not force and metadataLoadedAt > 0 and (nowSeconds() - metadataLoadedAt) < Config.CacheSeconds then
        return true
    end

    local roleStatus, roles, roleError = discordRequest('GET', ('/guilds/%s/roles'):format(SETTINGS.guildId))
    if roleStatus ~= 200 or type(roles) ~= 'table' then
        print(('^1[%s] Discord-rollen ophalen mislukt: %s^7'):format(RESOURCE, roleError or roleStatus))
        return false
    end

    local channelStatus, channels, channelError = discordRequest('GET', ('/guilds/%s/channels'):format(SETTINGS.guildId))
    if channelStatus ~= 200 or type(channels) ~= 'table' then
        print(('^1[%s] Discord-kanalen ophalen mislukt: %s^7'):format(RESOURCE, channelError or channelStatus))
        return false
    end

    rebuildRoleCache(roles)
    rebuildChannelCache(channels)
    metadataLoadedAt = nowSeconds()
    return true
end

local function roleKeysFromMember(member)
    local keys = {}
    for _, roleId in ipairs(member.roles or {}) do
        local key = roleKeysById[tostring(roleId)]
        if key then keys[key] = true end
    end
    return keys
end

local function fetchMember(discordId, force)
    local cached = memberCache[discordId]
    if not force and cached and (nowSeconds() - cached.fetchedAt) < Config.CacheSeconds then
        return cached.member, cached.roleKeys, nil
    end

    if not refreshGuildMetadata(false) then
        return nil, nil, 'Discord-metadata kon niet worden geladen.'
    end

    local status, member, requestError = discordRequest(
        'GET',
        ('/guilds/%s/members/%s'):format(SETTINGS.guildId, discordId)
    )

    if status == 404 then
        return nil, nil, 'not_member'
    end

    if status ~= 200 or type(member) ~= 'table' then
        return nil, nil, requestError or ('Discord HTTP %s'):format(status)
    end

    local roleKeys = roleKeysFromMember(member)
    memberCache[discordId] = {
        member = member,
        roleKeys = roleKeys,
        fetchedAt = nowSeconds(),
    }

    return member, roleKeys, nil
end

local function hasWhitelistRole(roleKeys)
    for roleKey in pairs(Config.WhitelistRoleKeys or {}) do
        if roleKeys[roleKey] then return true end
    end
    return false
end

local function allowedCommand(source)
    return source == 0 or IsPlayerAceAllowed(source, 'hextactics.admin')
end

local function permissionOverwrites(allowedRoles)
    if type(allowedRoles) ~= 'table' or #allowedRoles == 0 then return nil end

    local allow = tostring(VIEW_CHANNEL | SEND_MESSAGES | READ_MESSAGE_HISTORY | CONNECT | SPEAK)
    local overwrites = {
        {
            id = SETTINGS.guildId,
            type = 0,
            allow = '0',
            deny = tostring(VIEW_CHANNEL),
        },
    }

    for index = 1, #allowedRoles do
        local roleId = roleIdsByKey[allowedRoles[index]]
        if roleId then
            overwrites[#overwrites + 1] = {
                id = roleId,
                type = 0,
                allow = allow,
                deny = '0',
            }
        end
    end

    return overwrites
end

local function createMissingRoles()
    local status, roles, requestError = discordRequest('GET', ('/guilds/%s/roles'):format(SETTINGS.guildId))
    if status ~= 200 or type(roles) ~= 'table' then
        return false, requestError or 'Rollen konden niet worden opgehaald.'
    end

    local byName = roleNamesByExactName(roles)
    local defaults = Config.Provisioning.roleDefaults or {}

    for _, configuredRole in ipairs(Config.Roles or {}) do
        if not byName[configuredRole.name] then
            local createStatus, created, createError = discordRequest(
                'POST',
                ('/guilds/%s/roles'):format(SETTINGS.guildId),
                {
                    name = configuredRole.name,
                    permissions = defaults.permissions or '0',
                    hoist = defaults.hoist == true,
                    mentionable = defaults.mentionable == true,
                }
            )

            if createStatus ~= 200 or type(created) ~= 'table' then
                return false, ('Rol %s maken mislukt: %s'):format(configuredRole.name, createError or createStatus)
            end

            print(('^2[%s] Discord-rol aangemaakt: %s^7'):format(RESOURCE, configuredRole.name))
            Wait(300)
        end
    end

    return refreshGuildMetadata(true)
end

local function findCategory(channels, name)
    for _, channel in ipairs(channels or {}) do
        if channel.type == 4 and channel.name == name then return channel end
    end
    return nil
end

local function findChildChannel(channels, parentId, name, channelType)
    for _, channel in ipairs(channels or {}) do
        if channel.parent_id == parentId and channel.name == name and channel.type == channelType then
            return channel
        end
    end
    return nil
end

local function createMissingChannels()
    local status, channels, requestError = discordRequest('GET', ('/guilds/%s/channels'):format(SETTINGS.guildId))
    if status ~= 200 or type(channels) ~= 'table' then
        return false, requestError or 'Kanalen konden niet worden opgehaald.'
    end

    for categoryIndex, configuredCategory in ipairs(Config.Provisioning.categories or {}) do
        local category = findCategory(channels, configuredCategory.name)

        if not category then
            local categoryStatus, createdCategory, categoryError = discordRequest(
                'POST',
                ('/guilds/%s/channels'):format(SETTINGS.guildId),
                {
                    name = configuredCategory.name,
                    type = 4,
                    position = categoryIndex - 1,
                    permission_overwrites = permissionOverwrites(configuredCategory.allowedRoles),
                }
            )

            if categoryStatus ~= 201 or type(createdCategory) ~= 'table' then
                return false, ('Categorie %s maken mislukt: %s'):format(configuredCategory.name, categoryError or categoryStatus)
            end

            category = createdCategory
            channels[#channels + 1] = createdCategory
            print(('^2[%s] Discord-categorie aangemaakt: %s^7'):format(RESOURCE, configuredCategory.name))
            Wait(300)
        end

        for channelIndex, configuredChannel in ipairs(configuredCategory.channels or {}) do
            local channelType = configuredChannel.type == 'voice' and 2 or 0
            if not findChildChannel(channels, category.id, configuredChannel.name, channelType) then
                local payload = {
                    name = configuredChannel.name,
                    type = channelType,
                    parent_id = category.id,
                    position = channelIndex - 1,
                }

                if channelType == 0 and configuredChannel.topic then
                    payload.topic = safeText(configuredChannel.topic, 1024)
                end

                local channelStatus, createdChannel, channelError = discordRequest(
                    'POST',
                    ('/guilds/%s/channels'):format(SETTINGS.guildId),
                    payload
                )

                if channelStatus ~= 201 or type(createdChannel) ~= 'table' then
                    return false, ('Kanaal %s maken mislukt: %s'):format(configuredChannel.name, channelError or channelStatus)
                end

                channels[#channels + 1] = createdChannel
                print(('^2[%s] Discord-kanaal aangemaakt: %s/%s^7'):format(RESOURCE, configuredCategory.name, configuredChannel.name))
                Wait(300)
            end
        end
    end

    return refreshGuildMetadata(true)
end

local function sendDiscordLog(channelKey, title, description, fields)
    if not apiReady() then return false, 'Discord is niet geconfigureerd.' end
    if not refreshGuildMetadata(false) then return false, 'Kanaalcache kon niet worden geladen.' end

    local channelId = channelIdsByKey[channelKey]
    if not channelId then return false, ('Onbekend Discord-kanaal: %s'):format(channelKey) end

    local safeFields = {}
    if type(fields) == 'table' then
        for index = 1, math.min(#fields, 25) do
            local field = fields[index]
            safeFields[#safeFields + 1] = {
                name = safeText(field.name, 256),
                value = safeText(field.value, 1024),
                inline = field.inline == true,
            }
        end
    end

    local status, _, requestError = discordRequest(
        'POST',
        ('/channels/%s/messages'):format(channelId),
        {
            allowed_mentions = { parse = {} },
            embeds = {
                {
                    title = safeText(title, 256),
                    description = safeText(description, 4096),
                    color = 5793266,
                    fields = safeFields,
                    footer = { text = 'Delfzijl | HexTactics' },
                    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                },
            },
        }
    )

    return status == 200, requestError
end

local function refreshPlayer(source, force)
    source = tonumber(source)
    if not source or not GetPlayerName(source) then return false, 'Speler bestaat niet.' end

    local discordId = getDiscordId(source)
    if not discordId then return false, 'Geen Discord-identifier gevonden.' end

    local member, roleKeys, memberError = fetchMember(discordId, force == true)
    if not member then return false, memberError end

    local principal = getLicensePrincipal(source)
    if not principal then return false, 'Geen geldige FiveM-license gevonden.' end

    playerSessions[source] = playerSessions[source] or {}
    playerSessions[source].discordId = discordId
    playerSessions[source].member = member
    applySessionPrincipals(source, principal, roleKeys)
    return true, roleKeys
end

AddEventHandler('playerConnecting', function(playerName, _, deferrals)
    local source = source
    if not SETTINGS.enabled then return end

    deferrals.defer()
    Wait(0)
    deferrals.update('HexTactics: Discord-account en rollen controleren...')

    if not apiReady() then
        local message = 'Discord-koppeling is door de serverbeheerder nog niet volledig ingesteld.'
        print(('^1[%s] %s^7'):format(RESOURCE, message))
        if Config.FailClosed then deferrals.done(message) else deferrals.done() end
        return
    end

    local discordId = getDiscordId(source)
    if not discordId then
        if Config.RequireGuildMembership then
            deferrals.done(('Discord kon niet worden gevonden. Start Discord, koppel het aan FiveM en word lid: %s'):format(SETTINGS.inviteUrl))
        else
            deferrals.done()
        end
        return
    end

    local member, roleKeys, memberError = fetchMember(discordId, true)
    if not member then
        if memberError == 'not_member' then
            deferrals.done(('Je moet lid zijn van onze Discord-server: %s'):format(SETTINGS.inviteUrl))
        elseif Config.FailClosed then
            deferrals.done('De Discord-controle is tijdelijk niet beschikbaar. Probeer het zo opnieuw.')
        else
            deferrals.done()
        end
        return
    end

    if Config.BlockPendingScreening and member.pending == true then
        deferrals.done(('Rond eerst de Discord-lidmaatschapscontrole af: %s'):format(SETTINGS.inviteUrl))
        return
    end

    if Config.RequireWhitelistRole and not hasWhitelistRole(roleKeys) then
        deferrals.done(('Je hebt nog geen whitelistrol op Discord: %s'):format(SETTINGS.inviteUrl))
        return
    end

    local principal = getLicensePrincipal(source)
    if not principal then
        deferrals.done('Je FiveM-license kon niet veilig worden vastgesteld.')
        return
    end

    playerSessions[source] = {
        discordId = discordId,
        member = member,
        principal = principal,
        groups = {},
        roles = roleKeys,
    }
    applySessionPrincipals(source, principal, roleKeys)

    deferrals.done()

    CreateThread(function()
        Wait(1000)
        sendDiscordLog('join_leave', 'Speler verbonden', ('**%s** heeft verbinding gemaakt.'):format(safeText(playerName, 80)), {
            { name = 'Server-ID', value = tostring(source), inline = true },
            { name = 'Discord-ID', value = discordId, inline = true },
        })
    end)
end)

AddEventHandler('playerDropped', function(reason)
    local source = source
    local session = playerSessions[source]

    if SETTINGS.enabled and session then
        sendDiscordLog('join_leave', 'Speler vertrokken', ('**%s** heeft de server verlaten.'):format(safeText(GetPlayerName(source), 80)), {
            { name = 'Server-ID', value = tostring(source), inline = true },
            { name = 'Reden', value = safeText(reason, 500), inline = false },
        })
    end

    removeSessionPrincipals(source)
    playerSessions[source] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    for source in pairs(playerSessions) do removeSessionPrincipals(source) end
end)

RegisterCommand('discordsetup', function(source)
    if not allowedCommand(source) then return end
    if provisioningBusy then
        print(('^3[%s] Discord-setup draait al.^7'):format(RESOURCE))
        return
    end
    if not Config.Provisioning.enabled then
        print(('^3[%s] Provisioning staat uit in config.lua.^7'):format(RESOURCE))
        return
    end

    provisioningBusy = true
    CreateThread(function()
        print(('^5[%s] Veilige Discord-setup gestart; bestaande onderdelen worden niet verwijderd.^7'):format(RESOURCE))
        local rolesOk, rolesError = createMissingRoles()
        if not rolesOk then
            print(('^1[%s] Setup gestopt: %s^7'):format(RESOURCE, rolesError or 'rollenfout'))
            provisioningBusy = false
            return
        end

        local channelsOk, channelsError = createMissingChannels()
        if not channelsOk then
            print(('^1[%s] Setup gestopt: %s^7'):format(RESOURCE, channelsError or 'kanalenfout'))
            provisioningBusy = false
            return
        end

        print(('^2[%s] Discord-rollen en kanalen zijn gecontroleerd/aangemaakt.^7'):format(RESOURCE))
        provisioningBusy = false
    end)
end, false)

RegisterCommand('discordsync', function(source, args)
    if not allowedCommand(source) then return end
    local target = tonumber(args[1]) or source
    if target <= 0 then
        print(('^3[%s] Gebruik: discordsync [server-id]^7'):format(RESOURCE))
        return
    end

    CreateThread(function()
        local ok, result = refreshPlayer(target, true)
        print(ok
            and ('^2[%s] Discord-rollen opnieuw gesynchroniseerd voor source %d.^7'):format(RESOURCE, target)
            or ('^1[%s] Discord-sync mislukt voor source %d: %s^7'):format(RESOURCE, target, result or 'onbekend'))
    end)
end, false)

RegisterCommand('discordstatus', function(source)
    if not allowedCommand(source) then return end
    print(('^5========== %s status ==========^7'):format(RESOURCE))
    print(('enabled: %s'):format(tostring(SETTINGS.enabled)))
    print(('bot token ingesteld: %s'):format(tostring(SETTINGS.botToken ~= '')))
    print(('guild id ingesteld: %s'):format(tostring(SETTINGS.guildId ~= '')))
    print(('rolkoppelingen: %d'):format(#(Config.Roles or {})))
    print(('actieve spelerscache: %d'):format(#GetPlayers()))
end, false)

exports('HasRole', function(source, roleKey)
    source = tonumber(source)
    local session = source and playerSessions[source]
    return session and session.roles and session.roles[tostring(roleKey)] == true or false
end)

exports('GetRoleKeys', function(source)
    source = tonumber(source)
    local session = source and playerSessions[source]
    local result = {}
    if not session or type(session.roles) ~= 'table' then return result end
    for roleKey in pairs(session.roles) do result[#result + 1] = roleKey end
    table.sort(result)
    return result
end)

exports('GetDiscordId', function(source)
    source = tonumber(source)
    local session = source and playerSessions[source]
    return session and session.discordId or getDiscordId(source)
end)

exports('RefreshPlayer', function(source)
    return refreshPlayer(source, true)
end)

exports('Log', function(channelKey, title, description, fields)
    return sendDiscordLog(tostring(channelKey), title, description, fields)
end)

CreateThread(function()
    if not SETTINGS.enabled then
        print(('^3[%s] Uitgeschakeld. Zet ht_discord:enabled op true nadat botToken en guildId zijn ingesteld.^7'):format(RESOURCE))
        return
    end

    if not apiReady() then
        print(('^1[%s] Ingeschakeld maar botToken/guildId ontbreekt. De joincontrole gebruikt FailClosed=%s.^7'):format(RESOURCE, tostring(Config.FailClosed)))
        return
    end

    refreshGuildMetadata(true)

    while true do
        Wait(math.max(60, Config.RefreshOnlinePlayersSeconds or 300) * 1000)
        for _, sourceString in ipairs(GetPlayers()) do
            local source = tonumber(sourceString)
            if source then
                local ok, refreshError = refreshPlayer(source, true)
                if not ok then
                    print(('^3[%s] Periodieke sync source %d overgeslagen: %s^7'):format(RESOURCE, source, refreshError or 'onbekend'))
                end
                Wait(500)
            end
        end
    end
end)
