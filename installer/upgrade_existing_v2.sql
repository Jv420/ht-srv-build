-- Alleen nodig wanneer `ht_vehicle_registry` al bestond vóór Clean v2.0.0.
-- Maak vooraf een databaseback-up.

ALTER TABLE `ht_vehicle_registry`
    ADD COLUMN IF NOT EXISTS `enforcement_status`
        ENUM('clear','overdue','enforcement','impounded')
        NOT NULL DEFAULT 'clear'
        AFTER `insurance_expires_at`;
