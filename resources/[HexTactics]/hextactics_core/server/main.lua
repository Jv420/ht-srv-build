local ESX = exports['es_extended']:getSharedObject()

local function trim(value)
    value = tostring(value or '')
    return value:match('^%s*(.-)%s*$') or ''
end

local function normalizePlate(value)
    local normalized = trim(value):upper():gsub('[^A-Z0-9]', '')
    return normalized
end

local function parseIdentifier(identifier)
    identifier = tostring(identifier or ''):lower()

    local characterId = identifier:match('^char(%d+):')
    if characterId then
        identifier = identifier:gsub('^char%d+:', '', 1)
    end

    local identifierType, value = identifier:match('^([^:]+):(.+)$')
    if identifierType == 'license' or identifierType == 'license2' then
        identifier = value
    end

    return characterId and tonumber(characterId) or nil, identifier
end

local function identifiersMatch(left, right)
    local leftCharacter, leftBase = parseIdentifier(left)
    local rightCharacter, rightBase = parseIdentifier(right)

    if leftBase == '' or rightBase == '' or leftBase ~= rightBase then
        return false
    end

    -- Twee multicharacterrecords mogen nooit tussen verschillende slots lekken.
    if leftCharacter and rightCharacter then
        return leftCharacter == rightCharacter
    end

    -- Een oud record zonder char-prefix mag wel aan het actieve karakter worden gemigreerd.
    return true
end

local function getActiveIdentifier(source)
    local xPlayer = ESX.GetPlayerFromId(tonumber(source))
    if not xPlayer then return nil end

    if type(xPlayer.getIdentifier) == 'function' then
        local ok, identifier = pcall(xPlayer.getIdentifier)
        if ok and identifier and identifier ~= '' then
            return identifier
        end
    end

    return xPlayer.identifier
end

local function getPlayerIdentity(source)
    source = tonumber(source)
    if not source or source < 1 or GetPlayerPing(source) <= 0 then return nil end

    local candidates, seen, typed = {}, {}, {}

    local function add(identifier)
        identifier = tostring(identifier or '')
        if identifier == '' or seen[identifier] then return end

        seen[identifier] = true
        candidates[#candidates + 1] = identifier

        local identifierType = identifier:match('^([^:]+):')
        if identifierType and not typed[identifierType] then
            typed[identifierType] = identifier
        end
    end

    local activeIdentifier = getActiveIdentifier(source)
    add(activeIdentifier)

    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        add(identifier)
    end

    local characterId, baseIdentifier = parseIdentifier(activeIdentifier)

    return {
        source = source,
        activeIdentifier = activeIdentifier,
        characterId = characterId,
        baseIdentifier = baseIdentifier ~= '' and baseIdentifier or nil,
        license = typed.license,
        license2 = typed.license2,
        discord = typed.discord,
        fivem = typed.fivem,
        steam = typed.steam,
        candidates = candidates
    }
end

exports('NormalizePlate', normalizePlate)
exports('ParseIdentifier', parseIdentifier)
exports('IsIdentifierMatch', identifiersMatch)
exports('GetPlayerIdentity', getPlayerIdentity)
