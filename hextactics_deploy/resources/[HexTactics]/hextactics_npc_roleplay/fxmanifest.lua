fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'hextactics_npc_roleplay'
author 'HexTactics'
description 'Beveiligde Nederlandse politie-roleplay met game-NPCs'
version '1.0.0'

ui_page 'web/index.html'

files {
    'config.json',
    'web/index.html',
    'web/styles.css',
    'web/app.js'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

client_script 'client/main.js'

dependencies {
    'es_extended',
    'oxmysql',
    'ht_rdw'
}
