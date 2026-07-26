local function rewardAction(source, action)
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer then return false, 'Speler niet beschikbaar.' end
    local identifier = HTCrime.Identifier(xPlayer)
    local granted = {}

    if action.reward then
        local amount = math.random(math.floor(action.reward.min or 1), math.floor(action.reward.max or action.reward.min or 1))
        if not HTCrime.AddItem(source, action.reward.item, amount, { source='crime_contract', marked=true }) then
            return false, 'Je inventaris is vol.'
        end
        granted[#granted + 1] = ('%dx %s'):format(amount, action.reward.item)
    end

    if action.rewardPool then
        local numberOfRewards = math.min(#action.rewardPool, math.random(1, math.min(2, #action.rewardPool)))
        local selected = {}
        for _ = 1, numberOfRewards do
            local index
            repeat index = math.random(1, #action.rewardPool) until not selected[index]
            selected[index] = true
            local entry = action.rewardPool[index]
            local amount = math.random(math.floor(entry.min or 1), math.floor(entry.max or entry.min or 1))
            if HTCrime.AddItem(source, entry.item, amount, { source='crime_contract', stolen=true }) then
                granted[#granted + 1] = ('%dx %s'):format(amount, entry.item)
            end
        end
    end

    if action.moneyReward then
        local amount = math.random(math.floor(action.moneyReward.min or 1), math.floor(action.moneyReward.max or action.moneyReward.min or 1))
        HTCrime.AddCash(xPlayer, amount, 'Crime contract')
        granted[#granted + 1] = ('€%d'):format(amount)
    end

    HTCrime.ChangeProfile(identifier, action.rep or 0, action.heat or 0)
    return true, table.concat(granted, ', ')
end

local function consumeTools(source, action)
    if type(action.required) ~= 'table' then return true end
    if action.consumeAll then return HTCrime.RemoveItems(source, action.required) end
    local chance = tonumber(action.consumeChance) or 0
    if chance <= 0 or math.random(1, 100) > chance then return true end
    local candidates = {}
    for item in pairs(action.required) do candidates[#candidates + 1] = item end
    if #candidates == 0 then return true end
    return HTCrime.RemoveItem(source, candidates[math.random(1, #candidates)], 1)
end

RegisterNetEvent('htcrime:server:startAction', function(actionType, locationId)
    local source = source
    if HTCrime.Limited(source, 'startAction', 800) then return end
    if type(actionType) ~= 'string' or type(locationId) ~= 'string' then return end
    local action = Config.actions[actionType]
    local location = HTCrime.Location(actionType, locationId)
    if not action or not location then return HTCrime.Notify(source, 'Ongeldige activiteit.', 'error') end
    if not HTCrime.Near(source, location, tonumber(Config.maxInteractionDistance) or 6.0) then
        HTCrime.Audit(source, actionType, 'distance_rejected', { location=locationId })
        return
    end
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer then return end
    if HTCrime.IsPolice(xPlayer) then return HTCrime.Notify(source, 'Dienstpersoneel kan deze activiteit niet starten.', 'error') end
    local requiredPolice = math.max(0, tonumber(action.minPolice) or 0)
    if HTCrime.PoliceCount() < requiredPolice then return HTCrime.Notify(source, ('Minimaal %d politie nodig.'):format(requiredPolice), 'error') end
    local cooldownKey = HTCrime.CooldownKey(actionType, locationId)
    local remaining = HTCrime.CooldownRemaining(cooldownKey)
    if remaining > 0 then return HTCrime.Notify(source, ('Deze plek is nog %d minuten afgekoeld.'):format(math.ceil(remaining / 60)), 'error') end
    local hasItems, missing = HTCrime.HasItems(source, action.required)
    if not hasItems then return HTCrime.Notify(source, ('Je mist: %s.'):format(missing), 'error') end

    local token = HTCrime.CreateSession(source, {
        actionType = actionType,
        locationId = locationId,
        location = location,
        duration = math.max(3, tonumber(action.duration) or 10),
        cooldownKey = cooldownKey
    })
    HTCrime.Dispatch(source, ('HT-%s'):format(actionType:upper():sub(1, 8)), action.label, location, math.max(1, math.ceil((action.heat or 5) / 8)))
    HTCrime.LeaveEvidence(source, actionType, location, { locationId=locationId, phase='start' })
    HTCrime.Audit(source, actionType, 'started', { location=locationId, token=token })
    TriggerClientEvent('htcrime:client:actionStarted', source, {
        token=token, actionType=actionType, label=action.label, duration=math.max(3, tonumber(action.duration) or 10), location=location
    })
end)

RegisterNetEvent('htcrime:server:completeAction', function(token)
    local source = source
    if HTCrime.Limited(source, 'completeAction', 500) then return end
    local session, errorMessage = HTCrime.GetSession(source, token)
    if not session then return HTCrime.Notify(source, errorMessage, 'error') end
    local action = Config.actions[session.actionType]
    if not action then HTCrime.EndSession(token) return end
    if not HTCrime.Near(source, session.location, tonumber(Config.maxInteractionDistance) or 6.0) then
        HTCrime.EndSession(token)
        HTCrime.Audit(source, session.actionType, 'complete_distance_rejected', { location=session.locationId })
        return HTCrime.Notify(source, 'Je bent te ver van de activiteit verwijderd.', 'error')
    end
    local elapsed = os.time() - session.startedAt
    if elapsed + 1 < (session.duration or 3) then
        HTCrime.EndSession(token)
        HTCrime.Audit(source, session.actionType, 'too_fast', { elapsed=elapsed, expected=session.duration })
        return HTCrime.Notify(source, 'De activiteit werd te snel afgerond.', 'error')
    end
    local hasItems, missing = HTCrime.HasItems(source, action.required)
    if not hasItems then HTCrime.EndSession(token) return HTCrime.Notify(source, ('Je mist: %s.'):format(missing), 'error') end
    if not consumeTools(source, action) then HTCrime.EndSession(token) return HTCrime.Notify(source, 'Benodigde materialen konden niet worden verwerkt.', 'error') end
    local ok, result = rewardAction(source, action)
    if not ok then HTCrime.EndSession(token) return HTCrime.Notify(source, result, 'error') end
    HTCrime.SetCooldown(session.cooldownKey, action.cooldown or 0)
    HTCrime.LeaveEvidence(source, session.actionType, session.location, { locationId=session.locationId, phase='complete' }, (Config.evidenceChance or 35) + 10)
    HTCrime.Audit(source, session.actionType, 'completed', { location=session.locationId, reward=result })
    HTCrime.EndSession(token)
    HTCrime.Notify(source, ('Voltooid: %s'):format(result ~= '' and result or action.label), 'success')
    if session.actionType == 'smuggling_pickup' then TriggerClientEvent('htcrime:client:smugglingStage', source, 'delivery')
    elseif session.actionType == 'smuggling_delivery' then TriggerClientEvent('htcrime:client:smugglingStage', source, 'complete') end
    TriggerClientEvent('htcrime:client:actionFinished', source)
    TriggerClientEvent('htcrime:client:state', source, HTCrime.PublicState(source))
end)

RegisterNetEvent('htcrime:server:startSmuggling', function()
    local source = source
    if HTCrime.Limited(source, 'smuggling', 1200) then return end
    local pickup = HTCrime.RandomLocation('smuggling_pickup')
    local delivery = HTCrime.RandomLocation('smuggling_delivery')
    if not pickup or not delivery then return end
    TriggerClientEvent('htcrime:client:setRouteContract', source, {
        type='smuggling', pickup=pickup, delivery=delivery
    })
end)
