-- task 1: Получить информацию о всех гномах, которые входят в какой-либо отряд, вместе с информацией об их отрядах.

SELECT d.name       dwarf_name,
       d.age        dwarf_age,
       d.profession dwarf_profession,
       s.name       squad_name,
       s.mission    squad_mission
FROM dwarf_fortress.dwarves d
         LEFT JOIN dwarf_fortress.squads s ON d.squad_id = s.squad_id
WHERE s.squad_id IS NOT NULL;


-- task 2: Найти всех гномов с профессией "miner", которые не состоят ни в одном отряде.
SELECT d.name       dwarf_name,
       d.age        dwarf_age,
       d.profession dwarf_profession
FROM dwarf_fortress.dwarves d
WHERE d.squad_id IS NULL
  AND d.profession = 'miner';


-- task 3: Получить все задачи с наивысшим приоритетом, которые находятся в статусе "pending".

SELECT t.description,
       t.priority,
       t.status
FROM dwarf_fortress.tasks t
WHERE t.priority = (SELECT max(t.priority)
                    FROM dwarf_fortress.tasks t)
  AND t.status = 'pending';


-- task 4: Для каждого гнома, который владеет хотя бы одним предметом, получить количество предметов, которыми он владеет.

SELECT d.dwarf_id,
       d.name,
       d.profession,
       d.age,
       count(i.name) item_count
FROM dwarf_fortress.dwarves d
         LEFT JOIN dwarf_fortress.items i ON i.owner_id = d.dwarf_id
GROUP BY d.dwarf_id
HAVING count(i.name) > 0;


-- task 5: Получить список всех отрядов и количество гномов в каждом отряде. Также включите в выдачу отряды без гномов.

SELECT s.squad_id,
       s.name,
       s.mission,
       count(d.name)
FROM dwarf_fortress.squads s
         LEFT JOIN dwarf_fortress.dwarves d ON d.squad_id = s.squad_id
GROUP BY s.squad_id;


-- task 6: Получить список профессий с наибольшим количеством незавершённых задач ("pending" и "in_progress") у гномов этих профессий.

WITH TaskCounts AS (SELECT d.profession,
                           COUNT(t.task_id) AS pending_task_count
                    FROM dwarf_fortress.dwarves d
                             LEFT JOIN dwarf_fortress.tasks t ON d.dwarf_id = t.assigned_to
                    WHERE (t.status = 'pending'
                        OR t.status = 'in_progress')
                    GROUP BY d.profession)
SELECT profession,
       pending_task_count
FROM TaskCounts
WHERE pending_task_count = (SELECT MAX(pending_task_count) FROM TaskCounts);


-- task 7: Для каждого типа предметов узнать средний возраст гномов, владеющих этими предметами.

SELECT i.type, avg(d.age)
FROM dwarf_fortress.items i
         JOIN dwarf_fortress.dwarves d ON d.dwarf_id = i.owner_id
GROUP BY i.type


-- task 8: Найти всех гномов старше среднего возраста (по всем гномам в базе), которые не владеют никакими предметами.
SELECT d.name, d.profession, d.age
FROM dwarf_fortress.dwarves d
         LEFT JOIN dwarf_fortress.items i on d.dwarf_id = i.owner_id
WHERE i.item_id IS NULL
  AND d.age > (SELECT avg(d.age)
               FROM dwarf_fortress.dwarves d);