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
       ) AS related_entities
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
       ) AS related_entities
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
       ) AS related_entities
FROM military_squads AS ms;


-- Задача 1*: Анализ эффективности экспедиций.
--
-- Напишите запрос, который определит наиболее и наименее успешные экспедиции, учитывая:
-- Соотношение выживших участников к общему числу
-- Ценность найденных артефактов
-- Количество обнаруженных новых мест
-- Успешность встреч с существами (отношение благоприятных исходов к неблагоприятным)
-- Опыт, полученный участниками (сравнение навыков до и после)

SELECT json_build_object(
               'expedition_id', e.expedition_id,
               'destination', e.destination,
               'status', e.status,
               'departure_date', e.departure_date,
               'return_date', e.return_date,
               'expedition_duration',
               COALESCE(e.return_date, CURRENT_DATE) - e.departure_date,
               'survival_rate',
               ROUND(
                       COALESCE(
                               SUM(CASE WHEN em.survived = TRUE THEN 1 ELSE 0 END) * 100.0 /
                               NULLIF(COUNT(em.dwarf_id), 0),
                               0
                       ) || '%'
               ),
               'artifacts_value', COALESCE(SUM(ea.value), 0),
               'discovered_sites', COALESCE(
                       SUM(CASE
                               WHEN es.discovery_date BETWEEN e.departure_date AND e.return_date
                                   THEN 1
                               ELSE 0 END), 0
                                   ),
               'encounter_success_rate', ROUND(
                       COALESCE(
                               SUM(CASE WHEN ec.outcome = TRUE THEN 1 ELSE 0 END) * 100.0 /
                               NULLIF(COUNT(ec.creature_id), 0),
                               0
                       ) || '%'
                                         ),
               'skill_improvement',
               COALESCE((
                            -- Сумма опыта после экспедиции
                            SELECT SUM(ds_after.experience)
                            FROM expedition_members em2
                                     JOIN dwarf_skills ds_after ON em2.dwarf_id = ds_after.dwarf_id
                            WHERE em2.expedition_id = e.expedition_id
                              AND ds_after.date = (SELECT MAX(date)
                                                   FROM dwarf_skills
                                                   WHERE dwarf_id = ds_after.dwarf_id
                                                     AND skill_id = ds_after.skill_id
                                                     AND date <= COALESCE(e.return_date, CURRENT_DATE))), 0) -
               COALESCE((
                            -- Сумма опыта до экспедиции
                            SELECT SUM(ds_before.experience)
                            FROM expedition_members em2
                                     JOIN dwarf_skills ds_before ON em2.dwarf_id = ds_before.dwarf_id
                            WHERE em2.expedition_id = e.expedition_id
                              AND ds_before.date = (SELECT MAX(date)
                                                    FROM dwarf_skills
                                                    WHERE dwarf_id = ds_before.dwarf_id
                                                      AND skill_id = ds_before.skill_id
                                                      AND date <= e.departure_date)), 0
               ),
               json_object(
                       'member_ids', (SELECT json_arrayagg(em.dwarf_id)
                                      FROM expedition_members AS em
                                      WHERE em.expedition_id = e.expedition_id),
                       'artifact_ids', (SELECT json_arrayagg(se.artifact_id)
                                        FROM expedition_artifacts AS ea
                                        WHERE ea.expedition_id = e.expedition_id),
                       'operation_ids', (SELECT json_arrayagg(es.site_id)
                                         FROM expedition_sites AS es
                                         WHERE ea.expedition_id = e.expedition_id)
               ) as 'related_entities'
       )
FROM expeditions e
         LEFT JOIN expedition_members em ON e.expedition_id = em.expedition_id
         LEFT JOIN expedition_artifacts ea ON ea.expedition_id = e.expedition_id
         LEFT JOIN expedition_sites es ON es.expedition_id = e.expedition_id
         LEFT JOIN expedition_creatures ec ON ec.expedition_id = e.expedition_id
GROUP BY e.expedition_id
ORDER BY e.departure_date DESC;
