local function currentMarketIndex()
    local rotation = math.max(1, tonumber(Config.blackmarket.rotationHours) or 6) * 3600
    return (math.floor(os.time() / rotation) % #Config.locations.blackmarket) + 1
end

function HTCrime.CurrentBlackmarket()
    return Config.locations.blackmarket[currentMarketIndex()]
end

local function marketItem(itemName)
    for _, entry in ipairs(Config.blackmarket.items or {}) do if entry.item == itemName then return entry end end
end

local function fenceItem(itemName)
    for _, entry in ipairs(Config.blackmarket.fence or {}) do if entry.item == itemName then return entry end end
end

RegisterNetEvent('htcrime:server:marketBuy', function(itemName, amount)
    local source = source
    if HTCrime.Limited(source, 'marketBuy', 700) then return end
    local market = HTCrime.CurrentBlackmarket()
    local entry = type(itemName)=='string' and marketItem(itemName) or nil
    amount = math.max(1, math.min(10, math.floor(tonumber(amount) or 1)))
    if not entry or not HTCrime.Near(source, market, 5.0) then return end
    local xPlayer = HTCrime.GetPlayer(source)
    local profile = HTCrime.Profile(HTCrime.Identifier(xPlayer))
    if tonumber(profile.reputation) < (tonumber(entry.rep) or 0) then return HTCrime.Notify(source, 'Je reputatie is te laag.', 'error') end
    local price = math.max(0, math.floor(tonumber(entry.price) or 0)) * amount
    if HTCrime.InventoryCount(source, 'black_money') < price then return HTCrime.Notify(source, ('Je hebt %d zwart geld nodig.'):format(price), 'error') end
    if not HTCrime.RemoveItem(source, 'black_money', price) then return end
    if not HTCrime.AddItem(source, entry.item, amount, { vendor=market.id }) then
        HTCrime.AddItem(source, 'black_money', price)
        return HTCrime.Notify(source, 'Je inventaris is vol.', 'error')
    end
    HTCrime.Audit(source, 'blackmarket_buy', 'completed', { item=entry.item, amount=amount, price=price })
    HTCrime.Notify(source, ('Gekocht: %dx %s.'):format(amount, entry.label), 'success')
end)

RegisterNetEvent('htcrime:server:fenceSell', function(itemName, amount)
    local source = source
    if HTCrime.Limited(source, 'fenceSell', 700) then return end
    local market = HTCrime.CurrentBlackmarket()
    local entry = type(itemName)=='string' and fenceItem(itemName) or nil
    amount = math.max(1, math.min(25, math.floor(tonumber(amount) or 1)))
    if not entry or not HTCrime.Near(source, market, 5.0) then return end
    if HTCrime.InventoryCount(source, entry.item) < amount then return HTCrime.Notify(source, 'Je hebt onvoldoende goederen.', 'error') end
    if not HTCrime.RemoveItem(source, entry.item, amount) then return end
    local payout = math.floor(entry.price * amount * (0.85 + math.random() * 0.3))
    HTCrime.AddItem(source, 'black_money', payout, { source='fence' })
    HTCrime.ChangeProfile(HTCrime.Identifier(HTCrime.GetPlayer(source)), math.max(1, math.floor(amount / 2)), 1)
    HTCrime.Audit(source, 'fence_sell', 'completed', { item=entry.item, amount=amount, payout=payout })
    HTCrime.Notify(source, ('Heler betaalde %d zwart geld.'):format(payout), 'success')
end)

RegisterNetEvent('htcrime:server:convertMarked', function(amount)
    local source = source
    if HTCrime.Limited(source, 'convertMarked', 1200) then return end
    local market = HTCrime.CurrentBlackmarket()
    amount = math.max(1, math.min(math.floor(tonumber(amount) or 0), tonumber(Config.blackmarket.markedBillsMax) or 20000))
    if not market or not HTCrime.Near(source, market, 5.0) then return end
    if HTCrime.InventoryCount(source, 'marked_bills') < amount then return HTCrime.Notify(source, 'Je hebt onvoldoende gemarkeerde biljetten.', 'error') end
    if not HTCrime.RemoveItem(source, 'marked_bills', amount) then return end
    local percent = math.max(1, math.min(100, tonumber(Config.blackmarket.markedBillsExchangePercent) or 80))
    local payout = math.floor(amount * (percent / 100))
    if not HTCrime.AddItem(source, 'black_money', payout, { source='marked_exchange' }) then
        HTCrime.AddItem(source, 'marked_bills', amount)
        return HTCrime.Notify(source, 'Je inventaris kan het zwarte geld niet dragen.', 'error')
    end
    local xPlayer = HTCrime.GetPlayer(source)
    HTCrime.ChangeProfile(HTCrime.Identifier(xPlayer), math.max(1, math.floor(amount / 2500)), 3)
    HTCrime.LeaveEvidence(source, 'marked_money_exchange', market, { amount=amount, payout=payout }, 22)
    HTCrime.Audit(source, 'marked_bills_exchange', 'completed', { amount=amount, payout=payout })
    HTCrime.Notify(source, ('%d gemarkeerde biljetten omgezet naar %d zwart geld.'):format(amount, payout), 'success')
end)

RegisterNetEvent('htcrime:server:launder', function(amount, locationId)
    local source = source
    if HTCrime.Limited(source, 'launder', 1500) then return end
    local location = HTCrime.Location('moneywash', tostring(locationId))
    amount = math.max(1, math.min(math.floor(tonumber(amount) or 0), tonumber(Config.blackmarket.launderMax) or 15000))
    if not location or not HTCrime.Near(source, location, 5.0) then return end
    if HTCrime.InventoryCount(source, 'black_money') < amount then return HTCrime.Notify(source, 'Onvoldoende zwart geld.', 'error') end
    if not HTCrime.RemoveItem(source, 'black_money', amount) then return end
    local fee = math.floor(amount * ((tonumber(Config.blackmarket.launderFeePercent) or 25) / 100))
    local payout = math.max(0, amount - fee)
    local xPlayer = HTCrime.GetPlayer(source)
    HTCrime.AddCash(xPlayer, payout, 'Geld witwassen')
    HTCrime.ChangeProfile(HTCrime.Identifier(xPlayer), math.max(1, math.floor(amount / 2500)), 4)
    HTCrime.LeaveEvidence(source, 'money_laundering', location, { amount=amount }, 28)
    HTCrime.Audit(source, 'money_laundering', 'completed', { amount=amount, payout=payout })
    HTCrime.Notify(source, ('€%d witgewassen; €%d kosten.'):format(payout, fee), 'success')
end)

RegisterNetEvent('htcrime:server:streetSell', function(itemName)
    local source = source
    if HTCrime.Limited(source, 'streetSell', (tonumber(Config.streetSale.cooldownSeconds) or 18) * 1000) then return end
    local entry = type(itemName)=='string' and Config.streetSale.items[itemName] or nil
    if not entry then return end
    local xPlayer = HTCrime.GetPlayer(source)
    if not xPlayer or HTCrime.IsPolice(xPlayer) then return end
    if HTCrime.InventoryCount(source, itemName) < 1 then return HTCrime.Notify(source, 'Je hebt dit product niet.', 'error') end
    if not HTCrime.RemoveItem(source, itemName, 1) then return end
    local price = math.random(math.floor(entry.min), math.floor(entry.max))
    HTCrime.AddCash(xPlayer, price, 'Straatverkoop')
    HTCrime.ChangeProfile(HTCrime.Identifier(xPlayer), entry.rep or 1, entry.heat or 2)
    local coords = HTCrime.PlayerCoords(source)
    if coords and math.random(1,100) <= (tonumber(Config.streetSale.dispatchChance) or 22) then
        HTCrime.Dispatch(source, 'HT-DRUG', 'Melding verdachte straathandel', {x=coords.x,y=coords.y,z=coords.z}, 1)
    end
    HTCrime.LeaveEvidence(source, 'street_sale', {x=coords.x,y=coords.y,z=coords.z}, { item=itemName }, 18)
    HTCrime.Notify(source, ('Verkocht voor €%d.'):format(price), 'success')
end)

RegisterNetEvent('htcrime:server:craft', function(recipeName)
    local source = source
    if HTCrime.Limited(source, 'craft', 1000) then return end
    local recipes = {
        lockpick = { location='warehouse', required={metal_scrap=2,plastic=1}, output={item='lockpick',amount=1}, rep=0 },
        advanced_lockpick = { location='warehouse', required={metal_scrap=4,electronic_parts=2}, output={item='advanced_lockpick',amount=1}, rep=10 },
        plate_blank = { location='warehouse', required={metal_scrap=3}, output={item='plate_blank',amount=1}, rep=15 },
        hacking_device = { location='warehouse', required={electronic_parts=5,usb_crypto=1}, output={item='hacking_device',amount=1}, rep=25 }
    }
    local recipe = recipes[tostring(recipeName)]
    if not recipe then return end
    local profile = HTCrime.Profile(HTCrime.Identifier(HTCrime.GetPlayer(source)))
    if tonumber(profile.reputation) < recipe.rep then return HTCrime.Notify(source, 'Je reputatie is te laag voor dit ontwerp.', 'error') end
    local nearBench = false
    for _, location in ipairs(Config.locations.warehouse or {}) do if HTCrime.Near(source, location, 6.0) then nearBench = true break end end
    if not nearBench then return end
    local has, missing = HTCrime.HasItems(source, recipe.required)
    if not has then return HTCrime.Notify(source, ('Je mist: %s.'):format(missing), 'error') end
    if not HTCrime.RemoveItems(source, recipe.required) then return end
    if not HTCrime.AddItem(source, recipe.output.item, recipe.output.amount) then
        for item, amount in pairs(recipe.required) do HTCrime.AddItem(source, item, amount) end
        return HTCrime.Notify(source, 'Je inventaris is vol.', 'error')
    end
    HTCrime.Notify(source, ('Gemaakt: %s.'):format(recipe.output.item), 'success')
end)
