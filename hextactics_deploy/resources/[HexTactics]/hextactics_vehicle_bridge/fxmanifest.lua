fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'hextactics_vehicle_bridge'
author 'HexTactics'
description 'Veilige brug tussen Vehicle Suite, LC Fuel en andere garage-/voertuigresources'
version '1.0.0'

client_script 'client/main.js'
server_script 'server/main.lua'

dependencies {
    'ht_vehiclekeys',
    'ht_rdw'
}
