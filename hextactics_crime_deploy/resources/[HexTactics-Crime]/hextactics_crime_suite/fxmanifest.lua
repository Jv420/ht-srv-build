fx_version 'cerulean'
game 'gta5'

name 'hextactics_crime_suite'
author 'HexTactics'
description 'Modulaire Crime Edition voor ESX Legacy en ox met volledige servervalidatie.'
version '1.0.0'

lua54 'yes'

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
    'ox_inventory'
}

shared_scripts {
    '@ox_lib/init.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/core.lua',
    'server/contracts.lua',
    'server/vehicle.lua',
    'server/economy.lua',
    'server/gangs.lua',
    'server/prison.lua'
}

client_scripts {
    'client/main.js'
}

ui_page 'web/index.html'

files {
    'config.json',
    'web/index.html',
    'web/style.css',
    'web/app.js'
}
