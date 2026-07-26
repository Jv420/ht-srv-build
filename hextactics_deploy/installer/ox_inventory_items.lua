-- HexTactics-itemdefinities. Kopieer de entries naar ox_inventory/data/items.lua.
return {
    ['plate_blank'] = {
        label = 'Blanco kentekenplaat',
        weight = 800,
        stack = true,
        close = true,
        description = 'Onbedrukte plaat voor voertuigregistratie.'
    },

    ['vin_kit'] = {
        label = 'VIN-omkatset',
        weight = 1200,
        stack = true,
        close = true,
        description = 'Gereedschap en slagletters voor een voertuigidentiteit.'
    },

    ['blank_key'] = {
        label = 'Blanco autosleutel',
        weight = 80,
        stack = true,
        close = true,
        description = 'Programmeerbare sleutel zonder voertuigkoppeling.'
    },

    ['blank_vehicle_documents'] = {
        label = 'Blanco voertuigpapieren',
        weight = 50,
        stack = true,
        close = true,
        description = 'Onbedrukte documenten voor een voertuigregistratie.'
    },

    ['vehicle_documents'] = {
        label = 'Voertuigpapieren',
        weight = 50,
        stack = false,
        close = true,
        description = 'Officiële voertuigpapieren met kenteken- en VIN-gegevens.'
    },

    ['vehicle_tracker'] = {
        label = 'Voertuigtracker',
        weight = 250,
        stack = true,
        close = true,
        description = 'GPS-tracker die in een voertuig kan worden ingebouwd.'
    },

    ['tracker_tool'] = {
        label = 'Trackerdetector',
        weight = 650,
        stack = false,
        close = true,
        description = 'Detector en gereedschap om verborgen voertuigtrackers te verwijderen.'
    },
}
