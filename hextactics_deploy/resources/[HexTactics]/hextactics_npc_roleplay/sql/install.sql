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
