-- RDW-job voor de ESX Legacy-schema die door deze recipe wordt geïnstalleerd.
-- De statements zijn herhaalbaar door ON DUPLICATE KEY UPDATE.

INSERT INTO `jobs` (`name`, `label`, `type`, `whitelisted`)
VALUES ('rdw', 'RDW', 'civ', 0)
ON DUPLICATE KEY UPDATE
    `label` = VALUES(`label`),
    `type` = VALUES(`type`),
    `whitelisted` = VALUES(`whitelisted`);

INSERT INTO `job_grades`
    (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`)
VALUES
    ('rdw', 0, 'trainee', 'Stagiair', 350, '{}', '{}'),
    ('rdw', 1, 'inspector', 'APK-keurmeester', 500, '{}', '{}'),
    ('rdw', 2, 'senior', 'Senior keurmeester', 650, '{}', '{}'),
    ('rdw', 3, 'boss', 'Vestigingsmanager', 800, '{}', '{}')
ON DUPLICATE KEY UPDATE
    `name` = VALUES(`name`),
    `label` = VALUES(`label`),
    `salary` = VALUES(`salary`),
    `skin_male` = VALUES(`skin_male`),
    `skin_female` = VALUES(`skin_female`);
