fx_version 'cerulean'
game 'gta5'

name 'ht_discord'
author 'HexTactics'
description 'Beveiligde Discord-koppeling voor HexTactics: rollen, whitelist, ACE, kanaalstructuur en serverlogs.'
version '1.0.0'

lua54 'yes'

dependencies {
    'hextactics_core',
    'es_extended'
}

shared_script 'config.lua'
server_script 'server/main.lua'
