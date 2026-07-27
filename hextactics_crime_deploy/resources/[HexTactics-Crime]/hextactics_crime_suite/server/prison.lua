local function jailPlayer(targetSource, minutes, reason, jailedBy)
    local target = HTCrime.GetPlayer(targetSource)
    if not target then return false end
    minutes = math.max(1, math.min(240, math.floor(tonumber(minutes) or 1)))
    reason = type(reason)=='string' and reason:sub(1,160) or 'Geen reden opgegeven'
    local identifier = HTCrime.Identifier(target)
    MySQL.prepare.await([[
        INSERT INTO `ht_crime_jail` (`identifier`,`release_at`,`reason`,`jailed_by`)
        VALUES (?,DATE_ADD(NOW(),INTERVAL ? MINUTE),?,?)
        ON DUPLICATE KEY UPDATE `release_at`=VALUES(`release_at`),`reason`=VALUES(`reason`),`jailed_by`=VALUES(`jailed_by`)
    ]], { identifier, minutes, reason, jailedBy })
    TriggerClientEvent('htcrime:client:jail', targetSource, { remaining=minutes*60, reason=reason, prison=Config.prison })
    HTCrime.Audit(targetSource, 'jail', 'applied', { minutes=minutes, reason=reason, by=jailedBy })
    return true
end

RegisterCommand('crimejail', function(source, args)
    if source == 0 then return end
    local xPlayer = HTCrime.GetPlayer(source)
    if not HTCrime.IsPolice(xPlayer) and not IsPlayerAceAllowed(source, 'hextactics.admin') then return end
    local targetId, minutes = tonumber(args[1]), tonumber(args[2])
    if not targetId or not minutes then return HTCrime.Notify(source, 'Gebruik: /crimejail [id] [minuten] [reden]', 'error') end
    local reason = table.concat(args, ' ', 3)
    local targetPed = GetPlayerPed(targetId)
    local sourcePed = GetPlayerPed(source)
    if not IsPlayerAceAllowed(source, 'hextactics.admin') and (targetPed==0 or sourcePed==0 or #(GetEntityCoords(sourcePed)-GetEntityCoords(targetPed))>8.0) then
        return HTCrime.Notify(source, 'Arrestant staat te ver weg.', 'error')
    end
    if jailPlayer(targetId, minutes, reason, HTCrime.Identifier(xPlayer)) then HTCrime.Notify(source, 'Gevangenisstraf opgelegd.', 'success') end
end, false)

RegisterCommand('crimeunjail', function(source, args)
    if source == 0 then return end
    local xPlayer = HTCrime.GetPlayer(source)
    if not HTCrime.IsPolice(xPlayer) and not IsPlayerAceAllowed(source, 'hextactics.admin') then return end
    local targetId = tonumber(args[1])
    local target = HTCrime.GetPlayer(targetId)
    if not target then return end
    MySQL.update.await('DELETE FROM `ht_crime_jail` WHERE `identifier`=?', { HTCrime.Identifier(target) })
    TriggerClientEvent('htcrime:client:release', targetId, Config.prison.release)
end, false)

RegisterNetEvent('htcrime:server:requestJailState', function()
    local source = source
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer then return end
    local row = MySQL.single.await('SELECT GREATEST(0,UNIX_TIMESTAMP(`release_at`)-UNIX_TIMESTAMP()) AS `remaining`,`reason` FROM `ht_crime_jail` WHERE `identifier`=? AND `release_at`>NOW() LIMIT 1', { HTCrime.Identifier(xPlayer) })
    if row and tonumber(row.remaining) > 0 then TriggerClientEvent('htcrime:client:jail', source, { remaining=tonumber(row.remaining), reason=row.reason, prison=Config.prison }) end
end)

RegisterNetEvent('htcrime:server:prisonWork', function()
    local source = source
    if HTCrime.Limited(source, 'prisonWork', (Config.actions.prison_work.cooldown or 120)*1000) then return end
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer or not HTCrime.Near(source, Config.prison.work, 5.0) then return end
    local identifier = HTCrime.Identifier(xPlayer)
    local remaining = tonumber(MySQL.scalar.await('SELECT GREATEST(0,UNIX_TIMESTAMP(`release_at`)-UNIX_TIMESTAMP()) FROM `ht_crime_jail` WHERE `identifier`=? LIMIT 1', { identifier })) or 0
    if remaining <= 0 then return end
    local reduction = math.min(remaining, tonumber(Config.actions.prison_work.sentenceReduction) or 90)
    MySQL.update.await('UPDATE `ht_crime_jail` SET `release_at`=DATE_SUB(`release_at`,INTERVAL ? SECOND) WHERE `identifier`=?', { reduction, identifier })
    HTCrime.Notify(source, ('Straf met %d seconden verminderd.'):format(reduction), 'success')
    TriggerClientEvent('htcrime:client:jailTimeReduced', source, reduction)
end)

RegisterNetEvent('htcrime:server:startEscape', function()
    local source = source
    local action = Config.actions.prison_escape
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer or not HTCrime.Near(source, Config.prison.escape, 5.0) then return end
    local remaining = tonumber(MySQL.scalar.await('SELECT GREATEST(0,UNIX_TIMESTAMP(`release_at`)-UNIX_TIMESTAMP()) FROM `ht_crime_jail` WHERE `identifier`=? LIMIT 1', { HTCrime.Identifier(xPlayer) })) or 0
    if remaining <= 0 then return end
    if HTCrime.PoliceCount() < action.minPolice then return HTCrime.Notify(source, 'Onvoldoende politie voor een ontsnappingspoging.', 'error') end
    local has, missing = HTCrime.HasItems(source, action.required)
    if not has then return HTCrime.Notify(source, ('Je mist: %s.'):format(missing), 'error') end
    local key = HTCrime.CooldownKey('prison_escape', 'global')
    if HTCrime.CooldownRemaining(key) > 0 then return HTCrime.Notify(source, 'De ontsnappingsroute is recent gebruikt.', 'error') end
    local token = HTCrime.CreateSession(source, { actionType='prison_escape', location=Config.prison.escape, duration=action.duration, cooldownKey=key })
    HTCrime.Dispatch(source, 'HT-ESC', 'Mogelijke ontsnappingspoging gevangenis', Config.prison.escape, 3)
    TriggerClientEvent('htcrime:client:actionStarted', source, { token=token, actionType='prison_escape', label=action.label, duration=action.duration, location=Config.prison.escape })
end)

RegisterNetEvent('htcrime:server:completeEscape', function(token)
    local source = source
    local session = HTCrime.GetSession(source, token, 'prison_escape')
    if not session then return end
    if os.time()-session.startedAt+1 < session.duration or not HTCrime.Near(source, session.location, 6.0) then HTCrime.EndSession(token) return end
    local xPlayer = HTCrime.GetPlayer(source)
    if not HTCrime.RemoveItem(source, 'wire_cutter', 1) then HTCrime.EndSession(token) return end
    MySQL.update.await('DELETE FROM `ht_crime_jail` WHERE `identifier`=?', { HTCrime.Identifier(xPlayer) })
    HTCrime.ChangeProfile(HTCrime.Identifier(xPlayer), Config.actions.prison_escape.rep, Config.actions.prison_escape.heat)
    HTCrime.SetCooldown(session.cooldownKey, Config.actions.prison_escape.cooldown)
    HTCrime.LeaveEvidence(source, 'prison_escape', session.location, { escaped=true }, 75)
    HTCrime.EndSession(token)
    TriggerClientEvent('htcrime:client:release', source, { x=1625.23,y=2569.70,z=45.56,heading=265.0 })
    TriggerClientEvent('htcrime:client:actionFinished', source)
    HTCrime.Notify(source, 'Je bent ontsnapt. De politie is gewaarschuwd.', 'success')
end)

CreateThread(function()
    while true do
        Wait(60000)
        local expired = MySQL.query.await('SELECT `identifier` FROM `ht_crime_jail` WHERE `release_at`<=NOW() LIMIT 50') or {}
        for _, row in ipairs(expired) do
            for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
                if HTCrime.Identifier(xPlayer) == row.identifier then TriggerClientEvent('htcrime:client:release', xPlayer.source, Config.prison.release) end
            end
        end
        MySQL.update.await('DELETE FROM `ht_crime_jail` WHERE `release_at`<=NOW()')
    end
end)
