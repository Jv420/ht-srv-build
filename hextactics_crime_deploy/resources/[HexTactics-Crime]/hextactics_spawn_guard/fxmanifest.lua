fx_version 'cerulean'
game 'gta5'

name 'hextactics_spawn_guard'
author 'HexTactics'
description 'Veilige ESX multicharacter diagnostiek en eenmalige herstelpoging bij een vastgelopen joinflow.'
version '1.0.0'

lua54 'yes'

dependencies {
    'es_extended',
    'esx_multicharacter'
}

server_script 'server/main.lua'
client_script 'client/main.js'
