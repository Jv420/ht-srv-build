-- HexTactics Vehicle Suite v1.0.0
-- MariaDB / oxmysql
-- Importeer dit bestand één keer in dezelfde database als ESX.

CREATE TABLE IF NOT EXISTS `ht_vehicle_registry` (
    `plate` VARCHAR(12) NOT NULL,
    `vin` CHAR(17) NOT NULL,
    `owner` VARCHAR(80) NOT NULL,
    `registered_name` VARCHAR(100) DEFAULT NULL,
    `vehicle_model` VARCHAR(80) NOT NULL,
    `tracker_enabled` TINYINT(1) NOT NULL DEFAULT 0,
    `tracker_code` VARCHAR(24) DEFAULT NULL,
    `apk_expires_at` DATETIME DEFAULT NULL,
    `insurance_expires_at` DATETIME DEFAULT NULL,
    `tax_expires_at` DATETIME DEFAULT NULL,
    `stolen_status` TINYINT(1) NOT NULL DEFAULT 0,
    `registration_status` ENUM('active', 'suspended', 'exported', 'scrapped') NOT NULL DEFAULT 'active',
    `registered_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`plate`),
    UNIQUE KEY `uq_ht_vehicle_registry_vin` (`vin`),
    KEY `idx_ht_vehicle_registry_owner` (`owner`),
    KEY `idx_ht_vehicle_registry_apk` (`apk_expires_at`),
    KEY `idx_ht_vehicle_registry_insurance` (`insurance_expires_at`),
    KEY `idx_ht_vehicle_registry_tax` (`tax_expires_at`),
    KEY `idx_ht_vehicle_registry_stolen` (`stolen_status`),
    KEY `idx_ht_vehicle_registry_status` (`registration_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_vehicle_keys` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(12) NOT NULL,
    `identifier` VARCHAR(80) NOT NULL,
    `key_type` ENUM('owner', 'shared') NOT NULL DEFAULT 'shared',
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `revoked_at` DATETIME DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_ht_vehicle_keys_plate_identifier` (`plate`, `identifier`),
    KEY `idx_ht_vehicle_keys_identifier_active` (`identifier`, `active`),
    KEY `idx_ht_vehicle_keys_plate_active` (`plate`, `active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_vehicle_documents` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(12) NOT NULL,
    `owner` VARCHAR(80) NOT NULL,
    `document_number` VARCHAR(40) NOT NULL,
    `issued_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at` DATETIME DEFAULT NULL,
    `status` ENUM('valid', 'revoked', 'expired') NOT NULL DEFAULT 'valid',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_ht_vehicle_documents_plate` (`plate`),
    UNIQUE KEY `uq_ht_vehicle_documents_number` (`document_number`),
    KEY `idx_ht_vehicle_documents_owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_vehicle_inspections` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(12) NOT NULL,
    `inspector_identifier` VARCHAR(80) NOT NULL,
    `result` ENUM('passed', 'failed') NOT NULL,
    `engine_health` DECIMAL(8,2) NOT NULL,
    `body_health` DECIMAL(8,2) NOT NULL,
    `tank_health` DECIMAL(8,2) NOT NULL,
    `notes` VARCHAR(500) DEFAULT NULL,
    `inspected_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ht_vehicle_inspections_plate_date` (`plate`, `inspected_at`),
    KEY `idx_ht_vehicle_inspections_inspector` (`inspector_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_vehicle_fines` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `offender_identifier` VARCHAR(80) NOT NULL,
    `plate` VARCHAR(12) NOT NULL,
    `fine_type` VARCHAR(80) NOT NULL,
    `amount` INT UNSIGNED NOT NULL,
    `status` ENUM('open', 'paid', 'cancelled') NOT NULL DEFAULT 'open',
    `issued_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `paid_at` DATETIME DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_ht_vehicle_fines_offender_status` (`offender_identifier`, `status`),
    KEY `idx_ht_vehicle_fines_cooldown` (`offender_identifier`, `plate`, `fine_type`, `issued_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_vehicle_sales` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `buyer_identifier` VARCHAR(80) NOT NULL,
    `plate` VARCHAR(12) NOT NULL,
    `vin` CHAR(17) NOT NULL,
    `vehicle_model` VARCHAR(80) NOT NULL,
    `price` INT UNSIGNED NOT NULL,
    `seller` VARCHAR(100) NOT NULL,
    `sold_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ht_vehicle_sales_buyer` (`buyer_identifier`),
    KEY `idx_ht_vehicle_sales_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_vehicle_audit` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `actor_identifier` VARCHAR(80) NOT NULL,
    `action` VARCHAR(60) NOT NULL,
    `old_plate` VARCHAR(12) DEFAULT NULL,
    `new_plate` VARCHAR(12) DEFAULT NULL,
    `vin` CHAR(17) DEFAULT NULL,
    `details` LONGTEXT DEFAULT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ht_vehicle_audit_actor` (`actor_identifier`),
    KEY `idx_ht_vehicle_audit_plate` (`new_plate`),
    KEY `idx_ht_vehicle_audit_date` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Veilige migratie voor bestaande Vehicle Suite-installaties.
ALTER TABLE `ht_vehicle_registry`
    ADD COLUMN IF NOT EXISTS `tax_expires_at` DATETIME DEFAULT NULL AFTER `insurance_expires_at`,
    ADD COLUMN IF NOT EXISTS `stolen_status` TINYINT(1) NOT NULL DEFAULT 0 AFTER `tax_expires_at`,
    ADD COLUMN IF NOT EXISTS `registration_status` ENUM('active', 'suspended', 'exported', 'scrapped') NOT NULL DEFAULT 'active' AFTER `stolen_status`;

CREATE TABLE IF NOT EXISTS `ht_vehicle_history` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(12) NOT NULL,
    `event_type` VARCHAR(60) NOT NULL,
    `actor_identifier` VARCHAR(80) NOT NULL DEFAULT 'system',
    `details` LONGTEXT DEFAULT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ht_vehicle_history_plate_date` (`plate`, `created_at`),
    KEY `idx_ht_vehicle_history_event` (`event_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `hextactics_npc_cases` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `officer_identifier` VARCHAR(100) NOT NULL,
    `officer_name` VARCHAR(100) NULL,
    `npc_name` VARCHAR(100) NOT NULL,
    `npc_profile` LONGTEXT NULL,
    `action_type` VARCHAR(50) NOT NULL,
    `action_details` LONGTEXT NULL,
    `fine_amount` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_npc_cases_officer` (`officer_identifier`),
    KEY `idx_npc_cases_action` (`action_type`),
    KEY `idx_npc_cases_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
