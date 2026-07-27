# ht_discord

Beveiligde, modulaire Discord-koppeling voor Delfzijl | HexTactics.

## Waarom een losse resource?

`hextactics_core` blijft verantwoordelijk voor de algemene serverbasis. `ht_discord` kan apart worden gestart, gestopt of bijgewerkt en bevat alle Discord API-, rollen-, whitelist-, ACE-, kanaal- en logica.

## Functies

- Discord-lidmaatschap controleren tijdens `playerConnecting` met deferrals.
- Optionele whitelist op basis van exacte Discord-rollen.
- Tijdelijke Discord-rol naar FiveM ACE-principal synchronisatie per actieve sessie.
- Periodieke rollensynchronisatie voor online spelers.
- Beveiligde serverexports voor andere HexTactics-resources.
- Rollen, categorieën en kanalen veilig aanmaken met `discordsetup`.
- Bestaande Discord-onderdelen worden nooit automatisch verwijderd of hernoemd.
- Join/leave-logs en algemene embedlogging naar geconfigureerde kanalen.
- Geen clientevents en geen Discord-token in clientbestanden.

## Bot aanmaken

Maak in het Discord Developer Portal een application met een bot en voeg deze toe aan jouw Discord-server.

Benodigde botrechten:

- View Channels
- Send Messages
- Embed Links
- Read Message History
- Manage Roles
- Manage Channels

Plaats de botrol boven alle rollen die de bot moet kunnen beheren of uitdelen. Activeer `Server Members Intent` wanneer je later functies toevoegt die de volledige ledenlijst opvragen. De huidige koppeling haalt spelers individueel op via hun Discord-ID.

## server.cfg

Gebruik `set`, nooit `setr`, voor het bot-token. Een `setr`-waarde wordt naar clients gerepliceerd.

```cfg
sets Discord "https://discord.gg/cnbhkHphay"

set ht_discord:enabled "true"
set ht_discord:guildId "JOUW_DISCORD_SERVER_ID"
set ht_discord:botToken "JOUW_BOT_TOKEN"
set ht_discord:invite "https://discord.gg/cnbhkHphay"

# Beperk het lezen van het geheime token tot deze resource.
add_convar_permission ht_discord read ht_discord:botToken

# ht_discord mag tijdelijke ACE-principals beheren.
add_ace resource.ht_discord command.add_principal allow
add_ace resource.ht_discord command.remove_principal allow

# Discordrolgroepen naar HexTactics-rechten.
add_ace group.ht_staff hextactics.staff allow
add_ace group.ht_moderator hextactics.moderator allow
add_ace group.ht_support hextactics.support allow
add_ace group.ht_developer hextactics.developer allow
add_ace group.ht_beta hextactics.beta allow
add_ace group.ht_creator hextactics.creator allow
add_ace group.ht_police hextactics.job.police allow
add_ace group.ht_ambulance hextactics.job.ambulance allow
add_ace group.ht_anwb hextactics.job.anwb allow
add_ace group.ht_business hextactics.business allow
add_ace group.ht_whitelisted hextactics.whitelisted allow

ensure hextactics_core
ensure ht_discord
```

## Eerste setup

1. Start de server met een geldige bot-token en guild-ID.
2. Voer in de txAdmin-serverconsole uit:

```text
discordstatus
discordsetup
```

3. Zet de botrol in Discord boven alle beheerde rollen.
4. Controleer de aangemaakte kanalen en stel eventueel aanvullende Discord-rechten in.
5. Laat `Config.RequireWhitelistRole = false` totdat de rol `Whitelisted` correct wordt gebruikt.
6. Zet deze optie daarna desgewenst op `true` en herstart `ht_discord`.

## Commands

```text
discordstatus
discordsetup
discordsync [server-id]
```

Deze commands werken vanuit de serverconsole of voor spelers met `hextactics.admin`.

## Serverexports

```lua
local hasPoliceRole = exports.ht_discord:HasRole(source, 'police')
local roleKeys = exports.ht_discord:GetRoleKeys(source)
local discordId = exports.ht_discord:GetDiscordId(source)
local ok, result = exports.ht_discord:RefreshPlayer(source)

exports.ht_discord:Log('crime_logs', 'Overval gestart', 'Een beveiligde overvalmelding.', {
    { name = 'Speler', value = GetPlayerName(source), inline = true },
})
```

Jobs worden niet blind door Discord gewijzigd. Politie-, ambulance- en ANWB-rollen leveren beveiligde ACE-rechten/exports die de betreffende jobscripts server-side kunnen controleren.

## Beveiliging

- Bot-token uitsluitend in een server-only convar.
- Geen token, rolgegevens of Discord API-calls op de client.
- Exacte rolnaamcontrole; dubbele rolnamen worden geweigerd.
- Discord API-rate limits worden afgehandeld.
- Rollen worden op de server opgehaald en gevalideerd.
- Tijdelijke principals worden bij disconnect en resource-stop verwijderd.
- Provisioning verwijdert nooit bestaande Discord-kanalen of rollen.
