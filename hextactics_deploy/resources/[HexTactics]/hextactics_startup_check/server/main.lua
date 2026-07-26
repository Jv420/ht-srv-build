local requiredResources = {'oxmysql','ox_lib','es_extended','ox_inventory','ox_target','hextactics_core','ht_vehiclekeys','ht_chopshop','ht_rdw','ht_customdealer','hextactics_vehicle_bridge','hextactics_npc_roleplay'}
local optionalResources = {'lc_fuel'}
local conflictingResources = {'ox_fuel','LegacyFuel','esx_inventory','esx_garage','zerodream_parking','idev_keys','p_vehiclekeys','iwa_policejob','ls_usedvehicles'}
local function statusColour(state) if state == 'started' then return '^2' end if state == 'starting' then return '^3' end return '^1' end
local function runCheck(source)
    local missing, conflicts, optionalMissing = {}, {}, {}
    print('^5========== HexTactics deploycontrole ==========^7')
    for _, resource in ipairs(requiredResources) do local state=GetResourceState(resource); print(('%s%-34s ^7%s'):format(statusColour(state),resource,state)); if state~='started' then missing[#missing+1]=resource end end
    for _, resource in ipairs(optionalResources) do local state=GetResourceState(resource); print(('%s%-34s ^7%s (optioneel/eigen asset)'):format(statusColour(state),resource,state)); if state~='started' then optionalMissing[#optionalMissing+1]=resource end end
    for _, resource in ipairs(conflictingResources) do local state=GetResourceState(resource); if state=='started' or state=='starting' then conflicts[#conflicts+1]=resource; print(('^1CONFLICT: %-25s %s^7'):format(resource,state)) end end
    if #missing==0 and #conflicts==0 then print('^2[HexTactics] Verplichte basiscontrole geslaagd.^7') else if #missing>0 then print(('^3[HexTactics] Niet gestart: %s^7'):format(table.concat(missing,', '))) end if #conflicts>0 then print(('^1[HexTactics] Schakel deze conflicten uit: %s^7'):format(table.concat(conflicts,', '))) end end
    if #optionalMissing>0 then print('^3[HexTactics] LC Fuel is niet automatisch meegeleverd. Upload jouw legale lc_fuel-resource handmatig.^7') end
    if source and source>0 then TriggerClientEvent('chat:addMessage',source,{args={'HexTactics',(#missing==0 and #conflicts==0) and 'Basiscontrole geslaagd. Bekijk de serverconsole voor LC Fuel en details.' or 'Er zijn ontbrekende resources of conflicten. Bekijk de serverconsole.'}}) end
end
RegisterCommand('hextacticscheck',function(source) if source>0 and not IsPlayerAceAllowed(source,'hextactics.admin') then return end runCheck(source) end,false)
CreateThread(function() Wait(20000); runCheck(0) end)
