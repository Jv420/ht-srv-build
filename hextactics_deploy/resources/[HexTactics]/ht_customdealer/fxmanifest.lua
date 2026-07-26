fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'HexTactics'
description 'Custom ESX-autoverkoop op een eigen locatie met proefritten en veilige serveraankopen'
version '1.0.0'

node_version '22'

files {
    'config.json',
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

ui_page 'web/index.html'

client_script 'client/main.js'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_inventory',
    'ht_vehiclekeys'
}
