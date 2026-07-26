-- Optioneel: alleen importeren wanneer de ESX-job `rdw` nog niet bestaat.
-- Controleer eventueel eerst jouw jobs- en job_grades-structuur.

INSERT INTO `jobs` (`name`, `label`)
VALUES ('rdw', 'RDW')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`)
VALUES
    ('rdw', 0, 'trainee', 'Stagiair', 350),
    ('rdw', 1, 'inspector', 'APK-keurmeester', 500),
    ('rdw', 2, 'senior', 'Senior keurmeester', 650),
    ('rdw', 3, 'boss', 'Vestigingsmanager', 800)
ON DUPLICATE KEY UPDATE
    `name` = VALUES(`name`),
    `label` = VALUES(`label`),
    `salary` = VALUES(`salary`);
