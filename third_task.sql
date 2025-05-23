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

WITH expedition_stats AS (SELECT e.expedition_id,
                                 e.destination,
                                 e.status,
                                 COUNT(em.dwarf_id)                                        AS total_members,
                                 SUM(CASE WHEN em.survived = TRUE THEN 1 ELSE 0 END)       AS survivors,
                                 COALESCE(SUM(ea.value), 0)                                AS artifacts_value,
                                 COUNT(DISTINCT es.site_id)                                AS discovered_sites,
                                 SUM(CASE WHEN ec.outcome = 'Favorable' THEN 1 ELSE 0 END) AS favorable_encounters,
                                 COUNT(ec.creature_id)                                     AS total_encounters,
                                 e.departure_date,
                                 e.return_date
                          FROM expeditions e
                                   LEFT JOIN
                               expedition_members em ON e.expedition_id = em.expedition_id
                                   LEFT JOIN
                               expedition_artifacts ea ON e.expedition_id = ea.expedition_id
                                   LEFT JOIN
                               expedition_sites es ON e.expedition_id = es.expedition_id
                                   LEFT JOIN
                               expedition_creatures ec ON e.expedition_id = ec.expedition_id
                          GROUP BY e.expedition_id, e.destination, e.status, e.departure_date, e.return_date),
     skills_progression AS (SELECT em.expedition_id,
                                   SUM(
                                           COALESCE(ds_after.level, 0) - COALESCE(ds_before.level, 0)
                                   ) AS total_skill_improvement
                            FROM expedition_members em
                                     JOIN
                                 dwarves d ON em.dwarf_id = d.dwarf_id
                                     JOIN
                                 dwarf_skills ds_before ON d.dwarf_id = ds_before.dwarf_id
                                     JOIN
                                 dwarf_skills ds_after ON d.dwarf_id = ds_after.dwarf_id
                                     AND ds_before.skill_id = ds_after.skill_id
                                     JOIN
                                 expeditions e ON em.expedition_id = e.expedition_id
                            WHERE ds_before.date < e.departure_date
                              AND ds_after.date > e.return_date
                            GROUP BY em.expedition_id)
SELECT es.expedition_id,
       es.destination,
       es.status,
       es.survivors                                                  AS surviving_members,
       es.total_members,
       ROUND((es.survivors::DECIMAL / es.total_members) * 100, 2)    AS survival_rate,
       es.artifacts_value,
       es.discovered_sites,
       COALESCE(ROUND((es.favorable_encounters::DECIMAL /
                       NULLIF(es.total_encounters, 0)) * 100, 2), 0) AS encounter_success_rate,
       COALESCE(sp.total_skill_improvement, 0)                       AS skill_improvement,
       EXTRACT(DAY FROM (es.return_date - es.departure_date))        AS expedition_duration,
       ROUND(
               (es.survivors::DECIMAL / es.total_members) * 0.3 +
               (es.artifacts_value / 1000) * 0.25 +
               (es.discovered_sites * 0.15) +
               COALESCE((es.favorable_encounters::DECIMAL /
                         NULLIF(es.total_encounters, 0)), 0) * 0.15 +
               COALESCE((sp.total_skill_improvement / es.total_members), 0) * 0.15,
               2
       )                                                             AS overall_success_score,
       JSON_OBJECT(
               'member_ids', (SELECT JSON_ARRAYAGG(em.dwarf_id)
                              FROM expedition_members em
                              WHERE em.expedition_id = es.expedition_id),
               'artifact_ids', (SELECT JSON_ARRAYAGG(ea.artifact_id)
                                FROM expedition_artifacts ea
                                WHERE ea.expedition_id = es.expedition_id),
               'site_ids', (SELECT JSON_ARRAYAGG(es2.site_id)
                            FROM expedition_sites es2
                            WHERE es2.expedition_id = es.expedition_id)
       )                                                             AS related_entities
FROM expedition_stats es
         LEFT JOIN
     skills_progression sp ON es.expedition_id = sp.expedition_id
ORDER BY overall_success_score DESC;


--Разработайте запрос, который анализирует эффективность каждой мастерской, учитывая:
-- Производительность каждого ремесленника (соотношение созданных продуктов к затраченному времени)
-- Эффективность использования ресурсов (соотношение потребляемых ресурсов к производимым товарам)
-- Качество производимых товаров (средневзвешенное по ценности)
-- Время простоя мастерской
-- Влияние навыков ремесленников на качество товаров

-- {
--     "workshop_id": 301,
--     "workshop_name": "Royal Forge",
--     "workshop_type": "Smithy",
--     "num_craftsdwarves": 4, **
--     "total_quantity_produced": 256, **
--     "total_production_value": 187500, **
--
--     "daily_production_rate": 3.41, **
--     "value_per_material_unit": 7.82, **
--     "workshop_utilization_percent": 85.33, **
--
--     "material_conversion_ratio": 1.56, **
--
--     "average_craftsdwarf_skill": 7.25, **
--
--     "skill_quality_correlation": 0.83,
--
--     "related_entities": {
--       "craftsdwarf_ids": [101, 103, 108, 115],
--       "product_ids": [801, 802, 803, 804, 805, 806],
--       "material_ids": [201, 204, 208, 210],
--       "project_ids": [701, 702, 703]
--     }
--   }

WITH products_stat AS (SELECT wp.workshop_id                                                workshop_id,
                              wp.product_id                                                 product_id,
                              COALESCE(SUM(wp.quantity), 0)                              AS quantity_sum_per_workshop,
                              COALESCE(SUM(p.value * wp.quantity), 0)                    AS value_sum_per_workshop,
                              ROUND(SUM(wp.quantity) /
                                    NULLIF(COUNT(DISTINCT DATE(wp.production_date)), 0)) AS avg_daily_production,
                              ROUND((COUNT(DISTINCT wp.production_date)::numeric /
                                     (CURRENT_DATE - MIN(wp.production_date) + 1)::numeric * 100,
                                     2
                                  ))                                                     AS working_days_percentage
                       FROM workshop_products wp
                                LEFT JOIN products p ON wp.product_id = p.product_id
                       GROUP BY wp.workshop_id),
     material_stats AS (SELECT wm.workshop_id,
                               SUM(wm.quantity) as material_quantity
                        FROM workshop_materials wm
                        WHERE wm.is_input IS TRUE
                        GROUP BY wm.workshop_id),
     craftdwarves_stat AS (SELECT wcd.workshop_id,
                                  AVG(ds.level) as avg_level
                           FROM workshop_craftdwarves wcd
                                    LEFT JOIN DWARF_SKILLS ds ON wcd.dwarf_id = ds.dwarf_id
                           GROUP BY wcd.workshop_id)
SELECT w.workshop_id,
       w.name,
       w.type,
       w.quality,
       COALESCE(COUNT(wcd.dward_id), 0)                                     AS num_craftsdwarves,
       COALESCE(ps.quantity_sum_per_workshop, 0)                            AS total_quantity_produced,
       COALESCE(ps.value_sum_per_workshop, 0)                               AS total_production_value,
       ROUND(ps.working_days_percentage, 2)                                 AS workshop_utilization_percent,
       ROUND(COALESCE(ps.value_sum_per_workshop::numeric
                          / NULLIF(ms.material_quantity, 0), 0), 2)         AS value_per_material_unit,
       ROUND(COALESCE(ms.material_quantity::numeric
                          / NULLIF(ps.quantity_sum_per_workshop, 0), 0), 2) AS material_conversion_ratio,
       ROUND(COALESCE(cds.avg_level, 0), 2)                                 AS average_craftsdwarf_skill,
       ROUND(cds.avg_level, w.quality) AS skill_quality_correlation,
       JSON_OBJECT(
               'craftsdwarf_ids', (SELECT JSON_ARRAYAGG(wcd.dwarf_id)
                                   FROM workshop_craftdwarves wcd
                                   WHERE wcd.workshop_id = w.workshop_id),
               'product_ids', (SELECT JSON_ARRAYAGG(wp.product_id)
                               FROM workshop_products wp
                               WHERE wp.workshop_id = w.workshop_id),
               'material_ids', (SELECT JSON_ARRAYAGG(wm.material_id)
                                FROM workshop_materials wm
                                WHERE wm.workshop_id = w.workshop_id),
               'project_ids', (SELECT JSON_ARRAYAGG(p.project_id)
                               FROM projects p
                               WHERE p.workshop_id = w.workshop_id)
       )                                                                    AS related_entities
FROM workhops w
         LEFT JOIN workshop_craftdwarves wcd ON wcd.workshop_id = w.workshop_id
         LEFT JOIN products_stat ps ON ps.workshop_id = w.workshop_id
         LEFT JOIN material_stats ms ON ms.workshop_id = w.workshop_id
         LEFT JOIN craftdwarves_stat cds ON cds.workshop_id = w.workshop_id
GROUP BY w.workhop_id, w.name, w.type, w.quality;

-- Right one

WITH workshop_activity AS (SELECT w.workshop_id,
                                  w.name                                                                AS workshop_name,
                                  w.type                                                                AS workshop_type,
                                  COUNT(DISTINCT wc.dwarf_id)                                           AS num_craftsdwarves,
                                  COUNT(DISTINCT wp.product_id)                                         AS products_produced,
                                  SUM(wp.quantity)                                                      AS total_quantity_produced,
                                  SUM(p.value * wp.quantity)                                            AS total_production_value,
                                  COUNT(DISTINCT wm.material_id)                                        AS materials_used,
                                  SUM(wm.quantity)                                                      AS total_materials_consumed,
                                  MAX(wp.production_date) - MIN(wc.assignment_date)                     AS production_timespan,
                                  -- Days with production vs. total days active
                                  COUNT(DISTINCT wp.production_date)                                    AS active_production_days,
                                  EXTRACT(DAY FROM (MAX(wp.production_date) - MIN(wc.assignment_date))) AS total_days
                           FROM workshops w
                                    LEFT JOIN
                                workshop_craftsdwarves wc ON w.workshop_id = wc.workshop_id
                                    LEFT JOIN
                                workshop_products wp ON w.workshop_id = wp.workshop_id
                                    LEFT JOIN
                                products p ON wp.product_id = p.product_id
                                    LEFT JOIN
                                workshop_materials wm ON w.workshop_id = wm.workshop_id AND wm.is_input = TRUE
                           GROUP BY w.workshop_id, w.name, w.type),
     craftsdwarf_productivity AS (SELECT wc.workshop_id,
                                         wc.dwarf_id,
                                         COUNT(DISTINCT p.product_id) AS products_created,
                                         AVG(p.quality::INTEGER)      AS avg_quality,
                                         SUM(p.value)                 AS total_value_created
                                  FROM workshop_craftsdwarves wc
                                           JOIN
                                       products p ON p.created_by = wc.dwarf_id
                                  GROUP BY wc.workshop_id, wc.dwarf_id),
     craftsdwarf_skills AS (SELECT wc.workshop_id,
                                   wc.dwarf_id,
                                   AVG(ds.level) AS avg_skill_level,
                                   MAX(ds.level) AS max_skill_level
                            FROM workshop_craftsdwarves wc
                                     JOIN
                                 dwarf_skills ds ON wc.dwarf_id = ds.dwarf_id
                                     JOIN
                                 skills s ON ds.skill_id = s.skill_id
                            WHERE s.category = 'Crafting'
                            GROUP BY wc.workshop_id, wc.dwarf_id),
     material_efficiency AS (SELECT w.workshop_id,
                                    SUM(CASE WHEN wm.is_input = TRUE THEN wm.quantity ELSE 0 END)         AS input_quantity,
                                    SUM(CASE WHEN wm.is_input = FALSE THEN wm.quantity ELSE 0 END)        AS output_quantity,
                                    COUNT(DISTINCT CASE WHEN wm.is_input = TRUE THEN wm.material_id END)  AS unique_inputs,
                                    COUNT(DISTINCT CASE WHEN wm.is_input = FALSE THEN wm.material_id END) AS unique_outputs
                             FROM workshops w
                                      LEFT JOIN
                                  workshop_materials wm ON w.workshop_id = wm.workshop_id
                             GROUP BY w.workshop_id)
SELECT wa.workshop_id,
       wa.workshop_name,
       wa.workshop_type,
       wa.num_craftsdwarves,
       wa.total_quantity_produced,
       wa.total_production_value,

       -- Productivity metrics
       ROUND(wa.total_quantity_produced::DECIMAL / NULLIF(wa.total_days, 0), 2)              AS daily_production_rate,
       ROUND(wa.total_production_value::DECIMAL / NULLIF(wa.total_materials_consumed, 0), 2) AS value_per_material_unit,
       ROUND((wa.active_production_days::DECIMAL / NULLIF(wa.total_days, 0)) * 100,
             2)                                                                              AS workshop_utilization_percent,

       -- Efficiency metrics
       ROUND(me.output_quantity::DECIMAL / NULLIF(me.input_quantity, 0),
             2)                                                                              AS material_conversion_ratio,

       -- Craftsdwarf skill influence
       ROUND(AVG(cs.avg_skill_level), 2)                                                     AS average_craftsdwarf_skill,

       -- Correlation between skill and productivity
       CORR(cs.avg_skill_level, cp.avg_quality)                                              AS skill_quality_correlation,

       -- Related entities for REST API
       JSON_OBJECT(
               'craftsdwarf_ids', (SELECT JSON_ARRAYAGG(wc.dwarf_id)
                                   FROM workshop_craftsdwarves wc
                                   WHERE wc.workshop_id = wa.workshop_id),
               'product_ids', (SELECT JSON_ARRAYAGG(DISTINCT wp.product_id)
                               FROM workshop_products wp
                               WHERE wp.workshop_id = wa.workshop_id),
               'material_ids', (SELECT JSON_ARRAYAGG(DISTINCT wm.material_id)
                                FROM workshop_materials wm
                                WHERE wm.workshop_id = wa.workshop_id),
               'project_ids', (SELECT JSON_ARRAYAGG(p.project_id)
                               FROM projects p
                               WHERE p.workshop_id = wa.workshop_id)
       )                                                                                     AS related_entities
FROM workshop_activity wa
         LEFT JOIN
     material_efficiency me ON wa.workshop_id = me.workshop_id
         LEFT JOIN
     craftsdwarf_skills cs ON wa.workshop_id = cs.workshop_id
         LEFT JOIN
     craftsdwarf_productivity cp ON wa.workshop_id = cp.workshop_id AND cs.dwarf_id = cp.dwarf_id
GROUP BY wa.workshop_id, wa.workshop_name, wa.workshop_type, wa.num_craftsdwarves,
         wa.total_quantity_produced, wa.total_production_value, wa.total_days,
         wa.active_production_days, wa.total_materials_consumed,
         me.input_quantity, me.output_quantity, me.unique_inputs, me.unique_outputs
ORDER BY (wa.total_production_value::DECIMAL / NULLIF(wa.total_materials_consumed, 0)) *
         (wa.active_production_days::DECIMAL / NULLIF(wa.total_days, 0)) DESC;


-- Создайте запрос, оценивающий эффективность военных отрядов на основе:
--  - Результатов всех сражений (победы/поражения/потери)
--  - Соотношения побед к общему числу сражений
--  - Навыков членов отряда и их прогресса
--  - Качества экипировки
--  - Истории тренировок и их влияния на результаты
--  - Выживаемости членов отряда в долгосрочной перспективе

WITH squad_stats AS (SELECT ms.squad_id,
                            ms.name                                                    squad_name,
                            ms.formation_type,
                            d.name                                                     leader_name,
                            COUNT(sb.report_id)                                        total_battles,
                            SUM(CASE WHEN sb.outcome = 'victory' THEN 1 ELSE 0 END)    victories_count,
                            SUM(CASE WHEN sb.outcome = 'defeat' THEN 1 ELSE 0 END)     defeats_count,
                            COUNT(sm.dward_id)                                         total_members,
                            COUNT(CASE WHEN sm.exit_date IS NULL THEN sm.dward_id END) active_members,
                            COUNT(CASE
                                      WHEN sm.exit_date IS NOT NULL AND sm.exit_reason = 'death'
                                          THEN sm.dwarf_id END)                        death_toll,
                            SUM(sb.casualities)                                        total_casualities,
                            SUM(sb.enemy_casualitites)                                 total_enemy_casualities
                     FROM military_squad ms
                              LEFT JOIN dwarves d ON d.dwarf_id = ms.leader_id
                              LEFT JOIN squad_battles sb ON sb.squad_id = ms.squad_id
                              LEFT JOIN squad_members sm ON sm.squad_id = ms.squad_id
                     GROUP BY ms.squad_id, ms.name, ms.formation_type, d.name),
     equipment_stats AS (SELECT sq.equipment_id,
                                sq.squad_id,
                                eq.quality
                         FROM squad_equipment sq
                                  LEFT JOIN equipment eq ON sq.equipment_id = eq.equipment_id),
     battle_members AS (SELECT sb.report_id, sb.squad_id, sm.dwarf_id
                        FROM squad_battler sb
                                 LEFT JOIN squad_members sm ON sm.squad_id = sb.squad_id
                        WHERE (sm.exit_date IS NULL AND sm.join_date >= sb.date)
                           OR sm.exit_date >= sb.date),
     combat_skill_progression AS (SELECT sb.squad_id,
                                         SUM(
                                                 COALESCE(ds_after.level, 0) - COALESCE(ds_before.level, 0)
                                         ) AS total_skill_improvement
                                  FROM squad_battles sb
                                           JOIN
                                       battle_members bm ON bm.squad_id = sb.squad_id
                                           JOIN
                                       dwarves d ON bm.dwarf_id = d.dwarf_id
                                           JOIN
                                       dwarf_skills ds_before ON d.dwarf_id = ds_before.dwarf_id
                                           JOIN
                                       dwarf_skills ds_after ON d.dwarf_id = ds_after.dwarf_id
                                           AND ds_before.skill_id = ds_after.skill_id
                                  WHERE ds_before.date < sb.date
                                    AND ds_after.date >= sb.return_date
                                  GROUP BY sb.report_id)
SELECT ss.squad_id,
       ss.squad_name,
       ss.formation_type,
       ss.leader_name,
       ss.total_battles,
       ss.victories_count                                                               victories,
       ROUND(COALESCE(ss.victories_count::numeric / NULLIF(ss.total_battles, 0), 0), 2) victory_percentage,
       ROUND(COALESCE(ss.total_casualities::numeric / NULLIF(ss.total_members), 0), 2)  casualty_rate,
       ROUND(COALESCE(ss.total_casualities::numeric / NULLIF(ss.total_enemy_casualities), 0),
             2)                                                                         casualty_exchange_ratio,
       COALESCE(ss.active_members, 0)                                                   current_members,
       COALESCE(ss.total_members, 0)                                                    total_members_ever,
       ROUND(COALESCE(ss.active_members::numeric / NULLIF(ss.total_members), 0), 2)     retention_rate,
       COALESCE(AVG(es.quality), 0)                                                     avg_equipment_quality,
       COALESCE(AVG(st.effectiveness), 0)                                               avg_training_effectivness,
       CORR(COALESCE(ss.victories_count::numeric / NULLIF(ss.total_battles, 0), 0),
            st.effectiveness)                                                           training_battle_correletaion,
       COALESCE(AVG(csp.total_skill_improvement), 0)                                    avg_total_skill_improvement
FROM squad_stats ss
         LEFT JOIN equipment_stats es ON es.squad_id = ss.squad_id
         LEFT JOIN squad_training st ON st.squad_id = ss.squad_id
         LEFT JOIN combat_skill_progression csp ON csp.squad_id = ss.squad_id
GROUP BY ss.squad_id, ss.squad_name, ss.formation_type
