-- возвращает информацию о гноме, включая идентификаторы всех его навыков,
-- текущих назначений, принадлежности к отрядам и используемого снаряжения.
SELECT d.dwarf_id   AS dwarf_id,
       d.name       AS name,
       d.age        AS age,
       d.profession AS profession,
       json_object(
               'skill_ids', (SELECT json_arrayagg(ds.skill_id)
                             FROM dwarf_skills ds
                             WHERE ds.dwarf_id = d.dwarf_id),
               'assignment_ids', (SELECT json_arrayagg(da.assignment_id)
                                  FROM dwarf_assignments da
                                  WHERE da.dwarf_id = d.dwarf_id),
               'squad_ids', (SELECT json_arrayagg(sm.squad_id)
                             FROM squad_members sm
                             WHERE sm.dwarf_id = d.dwarf_id),
               'equipment_ids', (SELECT json_arrayagg(de.equipment_id)
                                 FROM dwarf_equipment de
                                 WHERE de.dwarf_id = d.dwarf_id)
           )        AS related_entities
FROM Dwarves AS d;


--запрос для получения информации о мастерской, включая идентификаторы
--назначенных ремесленников, текущих проектов, используемых и производимых ресурсов

SELECT w.workshop_id AS workshop_id,
       w.name        AS name,
       w.type        AS type,
       w.quality     AS quality,
       json_object(
               'craftsdwarf_ids', (SELECT json_arrayagg(wc.dwarf_id)
                                   FROM workshop_craftsdwarves AS wc
                                   WHERE wc.workshop_id = w.workshop_id),
               'project_ids', (SELECT json_arrayagg(p.project_id)
                               FROM projects AS p
                               WHERE p.workshop_id = w.workshop_id),
               'input_material_ids', (SELECT json_arrayagg(wm.material_id)
                                      FROM workshop_materials AS wm
                                      WHERE wm.workshop_id = w.workshop_id
                                        AND is_input),
               'output_product_ids', (SELECT json_arrayagg(wm.material_id)
                                      FROM workshop_materials AS wm
                                      WHERE wm.workshop_id = w.workshop_id
                                        AND NOT is_input)
           )         AS related_entities
FROM Workshops AS w;


--запрос, который возвращает информацию о военном отряде,
--включая идентификаторы всех членов отряда, используемого снаряжения,
--прошлых и текущих операций, тренировок

SELECT ms.squad_id       AS squad_id,
       ms.name           AS name,
       ms.formation_type AS formation_type,
       ms.leader_id      AS leader_id,
       json_object(
               'member_ids', (SELECT json_arrayagg(sm.dwarf_id)
                              FROM squad_members AS sm
                              WHERE sm.squad_id = ms.squad_id),
               'equipment_ids', (SELECT json_arrayagg(se.equipment_id)
                                 FROM squad_equipments AS se
                                 WHERE se.squad_id = ms.squad_id),
               'operation_ids', (SELECT json_arrayagg(so.operation_id)
                                 FROM squad_operations AS so
                                 WHERE so.squad_id = ms.squad_id
                                   AND so.start_date <= CURRENT_DATE),
               'training_schedule_ids', (SELECT json_arrayagg(st.schedule_id)
                                         FROM squad_training AS st
                                         WHERE st.squad_id = ms.squad_id),
               'battle_report_ids', (SELECT json_arrayagg(sb.report_id)
                                     FROM squad_battles AS sb
                                     WHERE sb.squad_id = ms.squad_id)
           )             AS related_entities
FROM military_squads AS ms;
