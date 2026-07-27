# Veiligheidsnotities

Bij de controle zijn vijf ingevulde Discord-webhook-URL's en één ingevuld Discord-bottoken in de aangeleverde resources gevonden. Deze waarden zijn uit de schone ZIP verwijderd zodat ze niet onbedoeld worden gedeeld of misbruikt.

Aangepaste configuraties:
- `nass_serverstore/server/server.lua`
- `raytrixscripts-blackmarket/config.lua`
- `wlabs-tablet/config.lua`
- `NKHD_Lib/config/server.lua`
- `community_bridge/settings/serverConfig.lua`
- `tuff-loading/settings.lua`

Maak oude webhooks/tokens ongeldig in Discord en genereer alleen nieuwe waarden wanneer je de betreffende functies echt gebruikt. Zet secrets bij voorkeur als server-convar in `server.cfg` of een niet-gecommitteerd apart configuratiebestand; plaats ze niet opnieuw in een ZIP of GitHub-repository.

De statische scan vond daarna geen Discord-webhook in het geldige Discord-webhookformaat meer. Dit is geen volledige malware- of penetratietest van alle aangeleverde third-party resources.
