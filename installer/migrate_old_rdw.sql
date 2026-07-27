-- Alleen uitvoeren wanneer de oude tabel `vehicle_registrations` bestaat.
-- Maak vooraf een databaseback-up.

INSERT IGNORE INTO `ht_vehicle_registry`
    (`plate`, `vin`, `owner`, `registered_name`, `vehicle_model`, `tracker_enabled`, `enforcement_status`, `registered_at`, `updated_at`)
SELECT
    REPLACE(UPPER(`plate`), ' ', ''),
    `vin`,
    `owner_identifier`,
    `registered_name`,
    COALESCE(NULLIF(`vehicle_model`, ''), 'unknown'),
    0,
    COALESCE(`enforcement_status`, 'clear'),
    COALESCE(`registered_at`, CURRENT_TIMESTAMP),
    COALESCE(`updated_at`, CURRENT_TIMESTAMP)
FROM `vehicle_registrations`
WHERE `active` = 1;

INSERT INTO `ht_vehicle_keys` (`plate`, `identifier`, `key_type`, `active`)
SELECT
    REPLACE(UPPER(`plate`), ' ', ''),
    `owner_identifier`,
    'owner',
    1
FROM `vehicle_registrations`
WHERE `active` = 1
ON DUPLICATE KEY UPDATE
    `active` = 1,
    `key_type` = 'owner',
    `revoked_at` = NULL;
