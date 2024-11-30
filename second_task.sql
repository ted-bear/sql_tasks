-- task 1: Найдите все отряды, у которых нет лидера.

SELECT s.name
FROM dwarf_fortress.squads s
WHERE leader_id IS NULL;


-- task 2: Получите список всех гномов старше 150 лет, у которых профессия "Warrior".
SELECT d.name, d.age, d.profession
FROM dwarf_fortress.dwarves d
WHERE d.age > 150
  AND profession = 'Warrior';


-- task 3: Найдите гномов, у которых есть хотя бы один предмет типа "weapon".

SELECT d.dwarf_id, d.name, i.type, i.name item_name
FROM dwarf_fortress.dwarves d
         JOIN dwarf_fortress.items i ON d.dwarf_id = i.owner_id
WHERE i.type = 'weapon';


-- task 4: Получите количество задач для каждого гнома, сгруппировав их по статусу.

SELECT d.name, t.status, count(t.task_id)
FROM dwarf_fortress.dwarves d
         JOIN dwarf_fortress.tasks t on d.dwarf_id = t.assigned_to
GROUP BY d.name, t.status
ORDER BY d.name;


-- task 5: Найдите все задачи, которые были назначены гномам из отряда с именем "Guardians".

SELECT t.description, d.name, s.name
FROM dwarf_fortress.tasks t
         JOIN dwarf_fortress.dwarves d ON d.dwarf_id = t.assigned_to
         JOIN dwarf_fortress.squads s ON d.squad_id = s.squad_id
WHERE s.name = 'Guardians';


-- task 6: Выведите всех гномов и их ближайших родственников, указав тип родственных отношений.

SELECT d.name, dd.name name_relation, r.relationship
FROM dwarf_fortress.dwarves d
         JOIN dwarf_fortress.relationships r ON d.dwarf_id = r.dwarf_id
         JOIN dwarf_fortress.dwarves dd ON r.related_to = dd.dwarf_id;


