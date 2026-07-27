local function gangForIdentifier(identifier)
    return MySQL.single.await([[
        SELECT g.`id`,g.`name`,g.`tag`,g.`color`,g.`reputation`,m.`rank`
        FROM `ht_crime_gang_members` m JOIN `ht_crime_gangs` g ON g.`id`=m.`gang_id`
        WHERE m.`identifier`=? LIMIT 1
    ]], { identifier })
end

RegisterNetEvent('htcrime:server:createGang', function(name, tag)
    local source = source
    if HTCrime.Limited(source, 'createGang', 2000) then return end
    local xPlayer = HTCrime.GetPlayer(source)
    local identifier = HTCrime.Identifier(xPlayer)
    if gangForIdentifier(identifier) then return HTCrime.Notify(source, 'Je zit al in een gang.', 'error') end
    name = type(name)=='string' and name:gsub('[^%w%s%-]',''):sub(1,32) or ''
    tag = type(tag)=='string' and tag:upper():gsub('[^A-Z0-9]',''):sub(1,5) or ''
    if #name < 3 or #tag < 2 then return HTCrime.Notify(source, 'Ongeldige gangnaam of tag.', 'error') end
    local gangId = MySQL.insert.await('INSERT INTO `ht_crime_gangs` (`name`,`tag`,`owner_identifier`) VALUES (?,?,?)', { name, tag, identifier })
    if not gangId then return HTCrime.Notify(source, 'Gangnaam of tag bestaat al.', 'error') end
    MySQL.insert.await('INSERT INTO `ht_crime_gang_members` (`gang_id`,`identifier`,`rank`) VALUES (?,?,"leader")', { gangId, identifier })
    MySQL.update.await('UPDATE `ht_crime_profiles` SET `gang_id`=? WHERE `identifier`=?', { gangId, identifier })
    HTCrime.Notify(source, ('Gang %s [%s] opgericht.'):format(name, tag), 'success')
    TriggerClientEvent('htcrime:client:state', source, HTCrime.PublicState(source))
end)

RegisterNetEvent('htcrime:server:inviteGang', function(targetId)
    local source = source
    if HTCrime.Limited(source, 'gangInvite', 1000) then return end
    targetId = tonumber(targetId)
    local xPlayer, target = HTCrime.GetPlayer(source), HTCrime.GetPlayer(targetId)
    if not xPlayer or not target or source == targetId then return end
    local sourcePed, targetPed = GetPlayerPed(source), GetPlayerPed(targetId)
    if sourcePed == 0 or targetPed == 0 or #(GetEntityCoords(sourcePed)-GetEntityCoords(targetPed)) > 5.0 then return HTCrime.Notify(source, 'Speler staat te ver weg.', 'error') end
    local gang = gangForIdentifier(HTCrime.Identifier(xPlayer))
    if not gang or gang.rank ~= 'leader' then return HTCrime.Notify(source, 'Alleen een leider kan uitnodigen.', 'error') end
    if gangForIdentifier(HTCrime.Identifier(target)) then return HTCrime.Notify(source, 'Deze speler zit al in een gang.', 'error') end
    HTCrime.PendingInvites[targetId] = { gangId=gang.id, expiresAt=os.time()+120, invitedBy=source }
    TriggerClientEvent('htcrime:client:gangInvite', targetId, { gangId=gang.id, name=gang.name, tag=gang.tag, source=source })
    HTCrime.Notify(source, 'Uitnodiging verstuurd.', 'success')
end)

RegisterNetEvent('htcrime:server:acceptGangInvite', function()
    local source = source
    local invite = HTCrime.PendingInvites[source]
    if not invite or os.time() > invite.expiresAt then HTCrime.PendingInvites[source]=nil return HTCrime.Notify(source, 'Uitnodiging verlopen.', 'error') end
    local xPlayer = HTCrime.GetPlayer(source)
    local identifier = HTCrime.Identifier(xPlayer)
    if gangForIdentifier(identifier) then return end
    MySQL.insert.await('INSERT IGNORE INTO `ht_crime_gang_members` (`gang_id`,`identifier`,`rank`) VALUES (?,?,"member")', { invite.gangId, identifier })
    MySQL.update.await('UPDATE `ht_crime_profiles` SET `gang_id`=? WHERE `identifier`=?', { invite.gangId, identifier })
    HTCrime.PendingInvites[source] = nil
    HTCrime.Notify(source, 'Je hebt de ganguitnodiging geaccepteerd.', 'success')
    TriggerClientEvent('htcrime:client:state', source, HTCrime.PublicState(source))
end)

RegisterNetEvent('htcrime:server:leaveGang', function()
    local source = source
    local xPlayer = HTCrime.GetPlayer(source)
    local identifier = HTCrime.Identifier(xPlayer)
    local gang = gangForIdentifier(identifier)
    if not gang then return end
    if gang.rank == 'leader' then return HTCrime.Notify(source, 'Een leider moet de gang eerst overdragen of ontbinden.', 'error') end
    MySQL.update.await('DELETE FROM `ht_crime_gang_members` WHERE `identifier`=?', { identifier })
    MySQL.update.await('UPDATE `ht_crime_profiles` SET `gang_id`=NULL WHERE `identifier`=?', { identifier })
    HTCrime.Notify(source, 'Je hebt de gang verlaten.', 'success')
end)

RegisterNetEvent('htcrime:server:startTerritory', function(locationId)
    local source = source
    if HTCrime.Limited(source, 'territory', 1500) then return end
    local location = HTCrime.Location('territory', tostring(locationId))
    local action = Config.actions.territory
    local xPlayer = HTCrime.GetPlayer(source)
    local gang = gangForIdentifier(HTCrime.Identifier(xPlayer))
    if not location or not gang or not HTCrime.Near(source, location, tonumber(location.radius) or 90.0) then return end
    if HTCrime.PoliceCount() < (tonumber(action.minPolice) or 2) then return HTCrime.Notify(source, 'Onvoldoende politie in dienst.', 'error') end
    local key = HTCrime.CooldownKey('territory', location.id)
    local remaining = HTCrime.CooldownRemaining(key)
    if remaining > 0 then return HTCrime.Notify(source, ('Territorium is nog %d minuten beschermd.'):format(math.ceil(remaining/60)), 'error') end
    local token = HTCrime.CreateSession(source, { actionType='territory', locationId=location.id, location=location, duration=action.duration, gangId=gang.id, cooldownKey=key })
    HTCrime.Dispatch(source, 'HT-TURF', ('Bendeconflict in %s'):format(location.label), location, 3)
    TriggerClientEvent('htcrime:client:actionStarted', source, { token=token, actionType='territory', label='Territorium overnemen', duration=action.duration, location=location })
end)

RegisterNetEvent('htcrime:server:completeTerritory', function(token)
    local source = source
    local session = HTCrime.GetSession(source, token, 'territory')
    if not session then return end
    if os.time()-session.startedAt+1 < session.duration or not HTCrime.Near(source, session.location, tonumber(session.location.radius) or 90.0) then HTCrime.EndSession(token) return end
    local xPlayer = HTCrime.GetPlayer(source)
    local gang = gangForIdentifier(HTCrime.Identifier(xPlayer))
    if not gang or gang.id ~= session.gangId then HTCrime.EndSession(token) return end
    MySQL.prepare.await([[
        INSERT INTO `ht_crime_territories` (`territory_id`,`gang_id`,`captured_at`) VALUES (?,?,NOW())
        ON DUPLICATE KEY UPDATE `gang_id`=VALUES(`gang_id`),`captured_at`=NOW()
    ]], { session.locationId, gang.id })
    MySQL.update.await('UPDATE `ht_crime_gangs` SET `reputation`=`reputation`+15 WHERE `id`=?', { gang.id })
    HTCrime.ChangeProfile(HTCrime.Identifier(xPlayer), Config.actions.territory.rep or 15, Config.actions.territory.heat or 20)
    HTCrime.SetCooldown(session.cooldownKey, Config.actions.territory.cooldown or 3600)
    HTCrime.LeaveEvidence(source, 'territory_capture', session.location, { gangId=gang.id, territory=session.locationId }, 60)
    HTCrime.EndSession(token)
    TriggerClientEvent('htcrime:client:actionFinished', source)
    HTCrime.Notify(source, ('%s is nu van %s.'):format(session.location.label, gang.name), 'success')
end)
