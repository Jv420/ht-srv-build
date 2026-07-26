CREATE TABLE IF NOT EXISTS `ht_crime_profiles` (
  `identifier` varchar(80) NOT NULL,
  `reputation` int unsigned NOT NULL DEFAULT 0,
  `heat` tinyint unsigned NOT NULL DEFAULT 0,
  `gang_id` int unsigned DEFAULT NULL,
  `last_seen` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`identifier`), KEY `idx_crime_profile_gang` (`gang_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_crime_cooldowns` (
  `action_key` varchar(100) NOT NULL,
  `available_at` datetime NOT NULL,
  PRIMARY KEY (`action_key`), KEY `idx_crime_cooldown_time` (`available_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_crime_contracts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `identifier` varchar(80) NOT NULL,
  `contract_type` varchar(50) NOT NULL,
  `state` enum('started','completed','failed','expired') NOT NULL DEFAULT 'started',
  `target_data` longtext DEFAULT NULL CHECK (json_valid(`target_data`)),
  `reward_data` longtext DEFAULT NULL CHECK (json_valid(`reward_data`)),
  `started_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `finished_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`), KEY `idx_crime_contract_identifier` (`identifier`,`started_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_crime_evidence` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `evidence_type` varchar(60) NOT NULL,
  `x` double NOT NULL, `y` double NOT NULL, `z` double NOT NULL,
  `fingerprint` varchar(32) DEFAULT NULL,
  `metadata` longtext DEFAULT NULL CHECK (json_valid(`metadata`)),
  `collected` tinyint(1) NOT NULL DEFAULT 0,
  `collected_by` varchar(80) DEFAULT NULL,
  `collected_at` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`), KEY `idx_crime_evidence_open` (`collected`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_crime_gangs` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(32) NOT NULL,
  `tag` varchar(5) NOT NULL,
  `owner_identifier` varchar(80) NOT NULL,
  `color` varchar(12) NOT NULL DEFAULT '#ff6538',
  `reputation` int unsigned NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`), UNIQUE KEY `uk_crime_gang_name` (`name`), UNIQUE KEY `uk_crime_gang_tag` (`tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_crime_gang_members` (
  `gang_id` int unsigned NOT NULL,
  `identifier` varchar(80) NOT NULL,
  `rank` enum('leader','officer','member') NOT NULL DEFAULT 'member',
  `joined_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`identifier`), KEY `idx_crime_gang_members_gang` (`gang_id`),
  CONSTRAINT `fk_crime_gang_members_gang` FOREIGN KEY (`gang_id`) REFERENCES `ht_crime_gangs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_crime_territories` (
  `territory_id` varchar(40) NOT NULL,
  `gang_id` int unsigned NOT NULL,
  `captured_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`territory_id`), KEY `idx_crime_territory_gang` (`gang_id`),
  CONSTRAINT `fk_crime_territory_gang` FOREIGN KEY (`gang_id`) REFERENCES `ht_crime_gangs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_crime_jail` (
  `identifier` varchar(80) NOT NULL,
  `release_at` datetime NOT NULL,
  `reason` varchar(160) NOT NULL,
  `jailed_by` varchar(80) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`identifier`), KEY `idx_crime_jail_release` (`release_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_crime_cloned_plates` (
  `original_plate` varchar(12) NOT NULL,
  `cloned_plate` varchar(12) NOT NULL,
  `identifier` varchar(80) NOT NULL,
  `expires_at` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`original_plate`), KEY `idx_crime_clone_plate` (`cloned_plate`), KEY `idx_crime_clone_expiry` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ht_crime_audit` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `identifier` varchar(80) NOT NULL,
  `source_id` int unsigned DEFAULT NULL,
  `action` varchar(80) NOT NULL,
  `result` varchar(40) NOT NULL,
  `metadata` longtext DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`), KEY `idx_crime_audit_identifier` (`identifier`,`created_at`), KEY `idx_crime_audit_action` (`action`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
