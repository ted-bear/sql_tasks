-- init tables

CREATE SCHEMA IF NOT EXISTS dwarf_fortress;

CREATE TABLE IF NOT EXISTS dwarf_fortress.Squads
(
    squad_id  SERIAL PRIMARY KEY,
    name      VARCHAR(100) NOT NULL,
    leader_id INT
);

CREATE TABLE IF NOT EXISTS dwarf_fortress.Dwarves
(
    dwarf_id   SERIAL PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    age        INT,
    profession VARCHAR(100),
    squad_id   INT,
    FOREIGN KEY (squad_id) REFERENCES dwarf_fortress.Squads (squad_id) ON DELETE SET NULL
);

ALTER TABLE dwarf_fortress.Squads
    ADD FOREIGN KEY (leader_id) REFERENCES dwarf_fortress.Dwarves (dwarf_id) ON DELETE SET NULL;


CREATE TABLE IF NOT EXISTS dwarf_fortress.Tasks
(
    task_id     SERIAL PRIMARY KEY,
    description TEXT NOT NULL,
    assigned_to INT,
    status      VARCHAR(50) CHECK (status IN ('pending', 'in_progress', 'completed')),
    FOREIGN KEY (assigned_to) REFERENCES dwarf_fortress.Dwarves (dwarf_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS dwarf_fortress.Items
(
    item_id  SERIAL PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    type     VARCHAR(50) CHECK (type IN ('weapon', 'armor', 'tool')),
    owner_id INT,
    FOREIGN KEY (owner_id) REFERENCES dwarf_fortress.Dwarves (dwarf_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS dwarf_fortress.Relationships
(
    dwarf_id     INT,
    related_to   INT,
    relationship VARCHAR(50),
    PRIMARY KEY (dwarf_id, related_to),
    FOREIGN KEY (dwarf_id) REFERENCES dwarf_fortress.Dwarves (dwarf_id) ON DELETE CASCADE,
    FOREIGN KEY (related_to) REFERENCES dwarf_fortress.Dwarves (dwarf_id) ON DELETE CASCADE
);


-- fill with data

INSERT INTO dwarf_fortress.Squads (name, leader_id)
VALUES ('The Company of Dwarves', 1),
       ('The Iron Hills', 2),
       ('The Lonely Mountain', 3),
       ('The Misty Mountains', 4),
       ('The Blue Mountains', 5),
       ('The Grey Mountains', 6),
       ('The Shire', NULL),
       ('The Woodland Realm', NULL),
       ('The Ironforge', NULL),
       ('The Stonefoot Clan', NULL);

INSERT INTO dwarf_fortress.Dwarves (name, age, profession, squad_id)
VALUES ('Thorin Oakenshield', 195, 'King', NULL),
       ('Gimli', 140, 'Warrior', 1),
       ('Balin', 178, 'Advisor', 1),
       ('Fili', 82, 'Scout', 1),
       ('Kili', 80, 'Archer', 1),
       ('Dwalin', 197, 'Warrior', 1),
       ('Oin', 167, 'Healer', 1),
       ('Gloin', 158, 'Warrior', 1),
       ('Bifur', 120, 'Miner', NULL),
       ('Bofur', 115, 'Merchant', NULL);


INSERT INTO dwarf_fortress.Tasks (description, assigned_to, status)
VALUES ('Retrieve the Arkenstone', 1, 'pending'),
       ('Defend the mountain', 2, 'in_progress'),
       ('Scout the area', 4, 'completed'),
       ('Gather supplies', 3, 'pending'),
       ('Build defenses', 5, 'in_progress'),
       ('Negotiate with elves', 6, 'completed'),
       ('Train the new recruits', 7, 'pending'),
       ('Explore the caves', 8, 'in_progress'),
       ('Repair the bridge', 9, 'completed'),
       ('Map the surrounding lands', 10, 'pending');

INSERT INTO dwarf_fortress.Items (name, type, owner_id)
VALUES ('Orcrist', 'weapon', 1),
       ('Glamdring', 'weapon', 2),
       ('Axe of Durin', 'weapon', 3),
       ('Dwarven Shield', 'armor', 4),
       ('Elven Bow', 'weapon', 5),
       ('Healing Potion', 'tool', 6),
       ('Mining Pick', 'tool', 7),
       ('Dwarven Boots', 'armor', 8),
       ('Gold Ingots', 'tool', NULL),
       ('Gemstone', 'tool', NULL);

INSERT INTO dwarf_fortress.Relationships (dwarf_id, related_to, relationship)
VALUES (1, 2, 'Друг'),
       (1, 3, 'Родственник'),
       (2, 4, 'Друг'),
       (3, 5, 'Супруг'),
       (4, 6, 'Друг'),
       (5, 7, 'Сослуживец'),
       (6, 8, 'Друг'),
       (7, 9, 'Сослуживец'),
       (8, 10, 'Друг'),
       (9, 1, 'Сослуживец');
