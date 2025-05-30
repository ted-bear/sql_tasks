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


-- Right one
WITH squad_battle_stats AS (SELECT sb.squad_id,
                                   COUNT(sb.report_id)                                     AS total_battles,
                                   SUM(CASE WHEN sb.outcome = 'Victory' THEN 1 ELSE 0 END) AS victories,
                                   SUM(CASE WHEN sb.outcome = 'Defeat' THEN 1 ELSE 0 END)  AS defeats,
                                   SUM(CASE WHEN sb.outcome = 'Retreat' THEN 1 ELSE 0 END) AS retreats,
                                   SUM(sb.casualties)                                      AS total_casualties,
                                   SUM(sb.enemy_casualties)                                AS total_enemy_casualties,
                                   MIN(sb.date)                                            AS first_battle,
                                   MAX(sb.date)                                            AS last_battle
                            FROM squad_battles sb
                            GROUP BY sb.squad_id),
     squad_member_history AS (SELECT sm.squad_id,
                                     COUNT(DISTINCT sm.dwarf_id)                                             AS total_members_ever,
                                     COUNT(DISTINCT CASE WHEN sm.exit_reason IS NULL THEN sm.dwarf_id END)   AS current_members,
                                     COUNT(DISTINCT CASE WHEN sm.exit_reason = 'Death' THEN sm.dwarf_id END) AS deaths,
                                     AVG(EXTRACT(DAY FROM
                                                 (COALESCE(sm.exit_date, CURRENT_DATE) - sm.join_date)))     AS avg_service_days
                              FROM squad_members sm
                              GROUP BY sm.squad_id),
     squad_skill_progression AS (SELECT sm.squad_id,
                                        sm.dwarf_id,
                                        AVG(ds_current.level - ds_join.level) AS avg_skill_improvement,
                                        MAX(ds_current.level)                 AS max_current_skill
                                 FROM squad_members sm
                                          JOIN
                                      dwarf_skills ds_join
                                      ON sm.dwarf_id = ds_join.dwarf_id AND ds_join.date <= sm.join_date
                                          JOIN
                                      dwarf_skills ds_current ON sm.dwarf_id = ds_current.dwarf_id
                                          AND ds_current.skill_id = ds_join.skill_id
                                          AND ds_current.date = (SELECT MAX(date)
                                                                 FROM dwarf_skills
                                                                 WHERE dwarf_id = sm.dwarf_id
                                                                   AND skill_id = ds_join.skill_id)
                                          JOIN
                                      skills s ON ds_join.skill_id = s.skill_id
                                 WHERE s.category IN ('Combat', 'Military')
                                 GROUP BY sm.squad_id, sm.dwarf_id),
     squad_equipment_quality AS (SELECT se.squad_id,
                                        AVG(e.quality::INTEGER)                            AS avg_equipment_quality,
                                        MIN(e.quality::INTEGER)                            AS min_equipment_quality,
                                        COUNT(DISTINCT e.equipment_id)                     AS unique_equipment_count,
                                        SUM(CASE WHEN e.type = 'Weapon' THEN 1 ELSE 0 END) AS weapon_count,
                                        SUM(CASE WHEN e.type = 'Armor' THEN 1 ELSE 0 END)  AS armor_count,
                                        SUM(CASE WHEN e.type = 'Shield' THEN 1 ELSE 0 END) AS shield_count
                                 FROM squad_equipment se
                                          JOIN
                                      equipment e ON se.equipment_id = e.equipment_id
                                 GROUP BY se.squad_id),
     squad_training_effectiveness AS (SELECT st.squad_id,
                                             COUNT(st.schedule_id)          AS total_training_sessions,
                                             AVG(st.effectiveness::DECIMAL) AS avg_training_effectiveness,
                                             SUM(st.duration_hours)         AS total_training_hours,
                                             -- Calculate if training improves battle outcomes
                                             CORR(
                                                     st.effectiveness::DECIMAL,
                                                     CASE WHEN sb.outcome = 'Victory' THEN 1 ELSE 0 END
                                             )                              AS training_battle_correlation
                                      FROM squad_training st
                                               LEFT JOIN
                                           squad_battles sb ON st.squad_id = sb.squad_id AND sb.date > st.date
                                      GROUP BY st.squad_id)
SELECT s.squad_id,
       s.name                                                                              AS squad_name,
       s.formation_type,
       -- Leadership effectiveness
       d.name                                                                              AS leader_name,
       sbs.total_battles,
       sbs.victories,
       sbs.defeats,
       ROUND((sbs.victories::DECIMAL / NULLIF(sbs.total_battles, 0)) * 100, 2)             AS victory_percentage,
       ROUND((sbs.total_casualties::DECIMAL / NULLIF(smh.total_members_ever, 0)) * 100, 2) AS casualty_rate,
       ROUND((sbs.total_enemy_casualties::DECIMAL / NULLIF(sbs.total_casualties, 1)), 2)   AS casualty_exchange_ratio,
       -- Member stats
       smh.current_members,
       smh.total_members_ever,
       ROUND((smh.current_members::DECIMAL / NULLIF(smh.total_members_ever, 0)) * 100, 2)  AS retention_rate,
       smh.avg_service_days,
       -- Equipment effectiveness
       seq.avg_equipment_quality,
       seq.min_equipment_quality,
       seq.weapon_count + seq.armor_count + seq.shield_count                               AS total_equipment_pieces,
       -- Training effectiveness
       ste.total_training_sessions,
       ste.total_training_hours,
       ste.avg_training_effectiveness,
       ste.training_battle_correlation,
       -- Skill progression
       ROUND(AVG(ssp.avg_skill_improvement), 2)                                            AS avg_combat_skill_improvement,
       ROUND(AVG(ssp.max_current_skill), 2)                                                AS avg_max_combat_skill,
       -- Years active
       EXTRACT(YEAR FROM (sbs.last_battle - sbs.first_battle))                             AS years_active,
       -- Overall effectiveness score
       ROUND(
               (sbs.victories::DECIMAL / NULLIF(sbs.total_battles, 0)) * 0.25 +
               (1 - (sbs.total_casualties::DECIMAL / NULLIF(smh.total_members_ever, 0))) * 0.20 +
               (smh.current_members::DECIMAL / NULLIF(smh.total_members_ever, 0)) * 0.15 +
               (seq.avg_equipment_quality::DECIMAL / 5) * 0.15 +
               (ste.avg_training_effectiveness) * 0.15 +
               (AVG(ssp.avg_skill_improvement) / 5) * 0.10,
               3
       )                                                                                   AS overall_effectiveness_score,
       -- Related entities for REST API
       JSON_OBJECT(
               'member_ids', (SELECT JSON_ARRAYAGG(sm.dwarf_id)
                              FROM squad_members sm
                              WHERE sm.squad_id = s.squad_id
                                AND sm.exit_date IS NULL),
               'equipment_ids', (SELECT JSON_ARRAYAGG(se.equipment_id)
                                 FROM squad_equipment se
                                 WHERE se.squad_id = s.squad_id),
               'battle_report_ids', (SELECT JSON_ARRAYAGG(sb.report_id)
                                     FROM squad_battles sb
                                     WHERE sb.squad_id = s.squad_id),
               'training_ids', (SELECT JSON_ARRAYAGG(st.schedule_id)
                                FROM squad_training st
                                WHERE st.squad_id = s.squad_id)
       )                                                                                   AS related_entities
FROM military_squads s
         JOIN
     dwarves d ON s.leader_id = d.dwarf_id
         LEFT JOIN
     squad_battle_stats sbs ON s.squad_id = sbs.squad_id
         LEFT JOIN
     squad_member_history smh ON s.squad_id = smh.squad_id
         LEFT JOIN
     squad_equipment_quality seq ON s.squad_id = seq.squad_id
         LEFT JOIN
     squad_training_effectiveness ste ON s.squad_id = ste.squad_id
         LEFT JOIN
     squad_skill_progression ssp ON s.squad_id = ssp.squad_id
GROUP BY s.squad_id, s.name, s.formation_type, d.name,
         sbs.total_battles, sbs.victories, sbs.defeats, sbs.total_casualties,
         sbs.total_enemy_casualties, sbs.first_battle, sbs.last_battle,
         smh.current_members, smh.total_members_ever, smh.avg_service_days,
         seq.avg_equipment_quality, seq.min_equipment_quality, seq.weapon_count,
         seq.armor_count, seq.shield_count,
         ste.total_training_sessions, ste.total_training_hours,
         ste.avg_training_effectiveness, ste.training_battle_correlation
ORDER BY overall_effectiveness_score DESC;


-- Разработайте запрос, анализирующий торговые отношения со всеми цивилизациями, оценивая:
-- - Баланс торговли с каждой цивилизацией за все время
-- - Влияние товаров каждого типа на экономику крепости
-- - Корреляцию между торговлей и дипломатическими отношениями
-- - Эволюцию торговых отношений во времени
-- - Зависимость крепости от определенных импортируемых товаров
-- - Эффективность экспорта продукции мастерских

-- {
--   "total_trading_partners": 5,
--   "all_time_trade_value": 15850000,
--   "all_time_trade_balance": 1250000,
--   "civilization_data": {
--     "civilization_trade_data": [
--       {
--         "civilization_type": "Human",
--         "total_caravans": 42,
--         "total_trade_value": 5240000, just sum
--         "trade_balance": 840000, from caravan is plus, else -- minus
--         "trade_relationship": "Favorable", max(date) and r_c
--         "diplomatic_correlation": 0.78,
--         "caravan_ids": [1301, 1305, 1308, 1312, 1315]
--       },
--       {
--         "civilization_type": "Elven",
--         "total_caravans": 38,
--         "total_trade_value": 4620000,
--         "trade_balance": -280000,
--         "trade_relationship": "Unfavorable",
--         "diplomatic_correlation": 0.42,
--         "caravan_ids": [1302, 1306, 1309, 1316, 1322]
--       }
--     ]
--   },
--   "critical_import_dependencies": {
--     "resource_dependency": [
--       {
--         "material_type": "Exotic Metals",
--         "dependency_score": 2850.5,
--         "total_imported": 5230,
--         "import_diversity": 4,
--         "resource_ids": [202, 208, 215]
--       },
--       {
--         "material_type": "Lumber",
--         "dependency_score": 1720.3,
--         "total_imported": 12450,
--         "import_diversity": 3,
--         "resource_ids": [203, 209, 216]
--       }
--     ]
--   },
--   "export_effectiveness": {
--     "export_effectiveness": [
--       {
--         "workshop_type": "Smithy",
--         "product_type": "Weapons",
--         "export_ratio": 78.5,
--         "avg_markup": 1.85,
--         "workshop_ids": [301, 305, 310]
--       },
--       {
--         "workshop_type": "Jewelery",
--         "product_type": "Ornaments",
--         "export_ratio": 92.3,
--         "avg_markup": 2.15,
--         "workshop_ids": [304, 309, 315]
--       }
--     ]
--   },
--   "trade_timeline": {
--     "trade_growth": [
--       {
--         "year": 205,
--         "quarter": 1,
--         "quarterly_value": 380000,
--         "quarterly_balance": 20000,
--         "trade_diversity": 3
--       },
--       {
--         "year": 205,
--         "quarter": 2,
--         "quarterly_value": 420000,
--         "quarterly_balance": 35000,
--         "trade_diversity": 4
--       }
--     ]
--   }
-- }

WITH civilization_trade_history AS (SELECT c.civilization_type,
                                           EXTRACT(YEAR FROM c.arrival_date)                                 AS trade_year,
                                           COUNT(DISTINCT c.caravan_id)                                      AS caravan_count,
                                           SUM(tt.value)                                                     AS total_trade_value,
                                           SUM(CASE WHEN cg.type = 'Import' THEN cg.value ELSE 0 END)        AS import_value,
                                           SUM(CASE WHEN cg.type = 'Export' THEN cg.value ELSE 0 END)        AS export_value,
                                           COUNT(DISTINCT cg.goods_id)                                       AS unique_goods_traded,
                                           COUNT(DISTINCT CASE WHEN cg.type = 'Import' THEN cg.goods_id END) AS unique_imports,
                                           COUNT(DISTINCT CASE WHEN cg.type = 'Export' THEN cg.goods_id END) AS unique_exports
                                    FROM caravans c
                                             JOIN
                                         trade_transactions tt ON c.caravan_id = tt.caravan_id
                                             JOIN
                                         caravan_goods cg ON c.caravan_id = cg.caravan_id
                                    GROUP BY c.civilization_type, EXTRACT(YEAR FROM c.arrival_date)),
     fortress_resource_dependency AS (SELECT cg.material_type,
                                             COUNT(DISTINCT cg.goods_id)  AS times_imported,
                                             SUM(cg.quantity)             AS total_imported,
                                             SUM(cg.value)                AS total_import_value,
                                             COUNT(DISTINCT c.caravan_id) AS caravans_importing,
                                             AVG(cg.price_fluctuation)    AS avg_price_fluctuation,
                                             -- Calculate resource dependency score
                                             (COUNT(DISTINCT cg.goods_id) *
                                              SUM(cg.quantity) *
                                              (1.0 / NULLIF(COUNT(DISTINCT c.civilization_type), 0))
                                                 )                        AS dependency_score
                                      FROM caravan_goods cg
                                               JOIN
                                           caravans c ON cg.caravan_id = c.caravan_id
                                      WHERE cg.type = 'Import'
                                      GROUP BY cg.material_type),
     diplomatic_trade_correlation AS (SELECT c.civilization_type,
                                             COUNT(DISTINCT de.event_id)                                            AS diplomatic_events,
                                             COUNT(DISTINCT CASE WHEN de.outcome = 'Positive' THEN de.event_id END) AS positive_events,
                                             COUNT(DISTINCT CASE WHEN de.outcome = 'Negative' THEN de.event_id END) AS negative_events,
                                             SUM(tt.value)                                                          AS total_trade_value,
                                             CORR(
                                                     de.relationship_change,
                                                     tt.value
                                             )                                                                      AS trade_diplomacy_correlation
                                      FROM caravans c
                                               JOIN
                                           trade_transactions tt ON c.caravan_id = tt.caravan_id
                                               JOIN
                                           diplomatic_events de ON c.civilization_type = de.civilization_type
                                      GROUP BY c.civilization_type),
     workshop_export_effectiveness AS (SELECT p.type                                                                  AS product_type,
                                              w.type                                                                  AS workshop_type,
                                              COUNT(DISTINCT p.product_id)                                            AS products_created,
                                              COUNT(DISTINCT CASE WHEN cg.goods_id IS NOT NULL THEN p.product_id END) AS products_exported,
                                              SUM(p.value)                                                            AS total_production_value,
                                              SUM(CASE WHEN cg.goods_id IS NOT NULL THEN cg.value ELSE 0 END)         AS export_value,
                                              AVG(CASE
                                                      WHEN cg.goods_id IS NOT NULL THEN (cg.value / p.value)
                                                      ELSE NULL END)                                                  AS avg_export_markup
                                       FROM products p
                                                JOIN
                                            workshops w ON p.workshop_id = w.workshop_id
                                                LEFT JOIN
                                            caravan_goods cg
                                            ON p.product_id = cg.original_product_id AND cg.type = 'Export'
                                       GROUP BY p.type, w.type),
     trade_timeline AS (SELECT EXTRACT(YEAR FROM c.arrival_date)                                                       AS year,
                               EXTRACT(QUARTER FROM c.arrival_date)                                                    AS quarter,
                               SUM(tt.value)                                                                           AS quarterly_trade_value,
                               COUNT(DISTINCT c.civilization_type)                                                     AS trading_civilizations,
                               SUM(CASE WHEN tt.balance_direction = 'Import' THEN tt.value ELSE 0 END)                 AS import_value,
                               SUM(CASE WHEN tt.balance_direction = 'Export' THEN tt.value ELSE 0 END)                 AS export_value,
                               LAG(SUM(tt.value))
                               OVER (ORDER BY EXTRACT(YEAR FROM c.arrival_date), EXTRACT(QUARTER FROM c.arrival_date)) AS previous_quarter_value
                        FROM caravans c
                                 JOIN
                             trade_transactions tt ON c.caravan_id = tt.caravan_id
                        GROUP BY EXTRACT(YEAR FROM c.arrival_date), EXTRACT(QUARTER FROM c.arrival_date))
SELECT
    -- Overall trade statistics
    (SELECT COUNT(DISTINCT civilization_type) FROM caravans)                       AS total_trading_partners,
    (SELECT SUM(total_trade_value) FROM civilization_trade_history)                AS all_time_trade_value,
    (SELECT SUM(export_value) - SUM(import_value) FROM civilization_trade_history) AS all_time_trade_balance,

    -- Civilization breakdown with REST API format
    JSON_OBJECT(
            'civilization_trade_data', (SELECT JSON_ARRAYAGG(
                                                       JSON_OBJECT(
                                                               'civilization_type', cth.civilization_type,
                                                               'total_caravans', SUM(cth.caravan_count),
                                                               'total_trade_value', SUM(cth.total_trade_value),
                                                               'trade_balance',
                                                               SUM(cth.export_value) - SUM(cth.import_value),
                                                               'trade_relationship', CASE
                                                                                         WHEN (SUM(cth.export_value) - SUM(cth.import_value)) > 0
                                                                                             THEN 'Favorable'
                                                                                         WHEN (SUM(cth.export_value) - SUM(cth.import_value)) < 0
                                                                                             THEN 'Unfavorable'
                                                                                         ELSE 'Balanced'
                                                                   END,
                                                               'diplomatic_correlation',
                                                               dtc.trade_diplomacy_correlation,
                                                               'unique_goods_traded', SUM(cth.unique_goods_traded),
                                                               'years_active', COUNT(DISTINCT cth.trade_year),
                                                               'caravan_ids', (SELECT JSON_ARRAYAGG(c.caravan_id)
                                                                               FROM caravans c
                                                                               WHERE c.civilization_type = cth.civilization_type)
                                                       )
                                               )
                                        FROM civilization_trade_history cth
                                                 LEFT JOIN diplomatic_trade_correlation dtc
                                                           ON cth.civilization_type = dtc.civilization_type
                                        GROUP BY cth.civilization_type, dtc.trade_diplomacy_correlation)
    )                                                                              AS civilization_data,

    -- Resource dependency analysis
    JSON_OBJECT(
            'resource_dependency', (SELECT JSON_ARRAYAGG(
                                                   JSON_OBJECT(
                                                           'material_type', frd.material_type,
                                                           'dependency_score', frd.dependency_score,
                                                           'total_imported', frd.total_imported,
                                                           'import_diversity', frd.caravans_importing,
                                                           'price_volatility', frd.avg_price_fluctuation,
                                                           'resource_ids', (SELECT JSON_ARRAYAGG(DISTINCT r.resource_id)
                                                                            FROM resources r
                                                                                     JOIN caravan_goods cg ON r.name = cg.material_type
                                                                            WHERE r.type = frd.material_type)
                                                   )
                                           )
                                    FROM fortress_resource_dependency frd
                                    ORDER BY frd.dependency_score DESC
                                    LIMIT 10)
    )                                                                              AS critical_import_dependencies,

    -- Workshop export analysis
    JSON_OBJECT(
            'export_effectiveness', (SELECT JSON_ARRAYAGG(
                                                    JSON_OBJECT(
                                                            'workshop_type', wee.workshop_type,
                                                            'product_type', wee.product_type,
                                                            'export_ratio', ROUND(
                                                                    (wee.products_exported::DECIMAL / NULLIF(wee.products_created, 0)) *
                                                                    100, 2),
                                                            'avg_markup', wee.avg_export_markup,
                                                            'total_export_value', wee.export_value,
                                                            'workshop_ids', (SELECT JSON_ARRAYAGG(w.workshop_id)
                                                                             FROM workshops w
                                                                             WHERE w.type = wee.workshop_type)
                                                    )
                                            )
                                     FROM workshop_export_effectiveness wee
                                     WHERE wee.products_created > 0
                                     ORDER BY wee.export_value DESC)
    )                                                                              AS export_effectiveness,

    -- Trade growth analysis
    JSON_OBJECT(
            'trade_growth', (SELECT JSON_ARRAYAGG(
                                            JSON_OBJECT(
                                                    'year', tt.year,
                                                    'quarter', tt.quarter,
                                                    'quarterly_value', tt.quarterly_trade_value,
                                                    'quarterly_balance', tt.export_value - tt.import_value,
                                                    'growth_from_previous', CASE
                                                                                WHEN tt.previous_quarter_value IS NULL
                                                                                    THEN NULL
                                                                                ELSE ROUND(
                                                                                        ((tt.quarterly_trade_value - tt.previous_quarter_value) /
                                                                                         NULLIF(tt.previous_quarter_value, 0)) *
                                                                                        100, 2)
                                                        END,
                                                    'trade_diversity', tt.trading_civilizations
                                            )
                                    )
                             FROM trade_timeline tt
                             ORDER BY tt.year, tt.quarter)
    )                                                                              AS trade_timeline,

    -- Trade impact on fortress economy
    JSON_OBJECT(
            'economic_impact', (SELECT JSON_OBJECT(
                                               'import_to_production_ratio', ROUND(
                    (SELECT SUM(import_value) FROM civilization_trade_history) /
                    NULLIF((SELECT SUM(total_production_value) FROM workshop_export_effectiveness), 0) * 100, 2
                                                                             ),
                                               'export_to_production_ratio', ROUND(
                                                       (SELECT SUM(export_value) FROM civilization_trade_history) /
                                                       NULLIF((SELECT SUM(total_production_value)
                                                               FROM workshop_export_effectiveness), 0) * 100, 2
                                                                             ),
                                               'trade_dependency_score', ROUND(
                                                       (SELECT SUM(total_trade_value) FROM civilization_trade_history) /
                                                       (SELECT COUNT(DISTINCT trade_year) FROM civilization_trade_history) /
                                                       (SELECT SUM(p.value) FROM products p) * 100, 2
                                                                         ),
                                               'most_profitable_exports', (SELECT JSON_ARRAYAGG(
                                                                                          JSON_OBJECT(
                                                                                                  'product_type',
                                                                                                  x.product_type,
                                                                                                  'total_value',
                                                                                                  x.export_value,
                                                                                                  'product_ids',
                                                                                                  (SELECT JSON_ARRAYAGG(p.product_id)
                                                                                                   FROM products p
                                                                                                            JOIN caravan_goods cg ON p.product_id = cg.original_product_id
                                                                                                   WHERE p.type = x.product_type
                                                                                                     AND cg.type = 'Export'
                                                                                                   LIMIT 100)
                                                                                          )
                                                                                  )
                                                                           FROM (SELECT product_type, SUM(export_value) AS export_value
                                                                                 FROM workshop_export_effectiveness
                                                                                 GROUP BY product_type
                                                                                 ORDER BY SUM(export_value) DESC
                                                                                 LIMIT 5) x),
                                               'most_expensive_imports', (SELECT JSON_ARRAYAGG(
                                                                                         JSON_OBJECT(
                                                                                                 'material_type',
                                                                                                 i.material_type,
                                                                                                 'total_value',
                                                                                                 i.import_value,
                                                                                                 'goods_ids',
                                                                                                 (SELECT JSON_ARRAYAGG(cg.goods_id)
                                                                                                  FROM caravan_goods cg
                                                                                                  WHERE cg.material_type = i.material_type
                                                                                                    AND cg.type = 'Import'
                                                                                                  LIMIT 100)
                                                                                         )
                                                                                 )
                                                                          FROM (SELECT cg.material_type,
                                                                                       SUM(cg.value) AS import_value
                                                                                FROM caravan_goods cg
                                                                                WHERE cg.type = 'Import'
                                                                                GROUP BY cg.material_type
                                                                                ORDER BY SUM(cg.value) DESC
                                                                                LIMIT 5) i)
                                       ))
    )                                                                              AS economic_impact,

    -- Recommendations based on trade analysis
    JSON_OBJECT(
            'trade_recommendations', (SELECT JSON_ARRAYAGG(
                                                     JSON_OBJECT(
                                                             'recommendation_type',
                                                             CASE
                                                                 WHEN r.dependency_score > 1000
                                                                     THEN 'Critical Dependency'
                                                                 WHEN r.dependency_score > 500 THEN 'High Dependency'
                                                                 WHEN r.dependency_score > 100
                                                                     THEN 'Moderate Dependency'
                                                                 ELSE 'Low Dependency'
                                                                 END,
                                                             'material_type', r.material_type,
                                                             'recommended_action',
                                                             CASE
                                                                 WHEN r.dependency_score > 1000
                                                                     THEN 'Develop domestic production'
                                                                 WHEN r.dependency_score > 500
                                                                     THEN 'Diversify import sources'
                                                                 WHEN r.dependency_score > 100
                                                                     THEN 'Maintain strategic reserves'
                                                                 ELSE 'Continue current trade strategy'
                                                                 END,
                                                             'potential_partners',
                                                             (SELECT JSON_ARRAYAGG(DISTINCT c.civilization_type)
                                                              FROM caravans c
                                                                       JOIN caravan_goods cg ON c.caravan_id = cg.caravan_id
                                                              WHERE cg.material_type = r.material_type
                                                                AND cg.type = 'Import'),
                                                             'resource_ids',
                                                             (SELECT JSON_ARRAYAGG(DISTINCT r2.resource_id)
                                                              FROM resources r2
                                                              WHERE r2.type = r.material_type)
                                                     )
                                             )
                                      FROM fortress_resource_dependency r
                                      ORDER BY r.dependency_score DESC
                                      LIMIT 10),
            'export_opportunities', (SELECT JSON_ARRAYAGG(
                                                    JSON_OBJECT(
                                                            'workshop_type', w.type,
                                                            'current_export_ratio', COALESCE(
                                                                    (SELECT ROUND(
                                                                                    (wee.products_exported::DECIMAL / NULLIF(wee.products_created, 0)) *
                                                                                    100, 2)
                                                                     FROM workshop_export_effectiveness wee
                                                                     WHERE wee.workshop_type = w.type
                                                                     LIMIT 1),
                                                                    0
                                                                                    ),
                                                            'potential_value', COALESCE(
                                                                    (SELECT SUM(p.value)
                                                                     FROM products p
                                                                              JOIN workshops w2 ON p.workshop_id = w2.workshop_id
                                                                              LEFT JOIN caravan_goods cg
                                                                                        ON p.product_id = cg.original_product_id AND cg.type = 'Export'
                                                                     WHERE w2.type = w.type
                                                                       AND cg.goods_id IS NULL),
                                                                    0
                                                                               ),
                                                            'recommended_civilizations',
                                                            (SELECT JSON_ARRAYAGG(DISTINCT c.civilization_type)
                                                             FROM caravans c
                                                                      JOIN caravan_goods cg ON c.caravan_id = cg.caravan_id
                                                             WHERE cg.type = 'Import'
                                                               AND c.civilization_type IN
                                                                   (SELECT DISTINCT c2.civilization_type
                                                                    FROM caravans c2
                                                                             JOIN trade_transactions tt ON c2.caravan_id = tt.caravan_id
                                                                             JOIN diplomatic_events de ON c2.civilization_type = de.civilization_type
                                                                    WHERE de.outcome = 'Positive')),
                                                            'workshop_ids', (SELECT JSON_ARRAYAGG(w2.workshop_id)
                                                                             FROM workshops w2
                                                                             WHERE w2.type = w.type)
                                                    )
                                            )
                                     FROM (SELECT DISTINCT type
                                           FROM workshops) w)
    )                                                                              AS trade_recommendations
FROM (SELECT 1) AS dummy;

-- Разработайте запрос, который комплексно анализирует безопасность крепости, учитывая:
-- - Историю всех атак существ и их исходов
-- - Эффективность защитных сооружений
-- - Соотношение между типами существ и результативностью обороны
-- - Оценку уязвимых зон на основе архитектуры крепости
-- - Корреляцию между сезонными факторами и частотой нападений
-- - Готовность военных отрядов и их расположение
-- - Эволюцию защитных способностей крепости со временем
--
-- Возможный вариант выдачи:

-- {
--   "total_recorded_attacks": 183,
--   "unique_attackers": 42,
--   "overall_defense_success_rate": 76.50,
--   "security_analysis": {
--     "threat_assessment": {
--       "current_threat_level": "Moderate",
--       "active_threats": [
--         {
--           "creature_type": "Goblin", *
--           "threat_level": 3, *
--           "last_sighting_date": "0205-08-12", *
--           "territory_proximity": 1.2, *
--           "estimated_numbers": 35, *
--           "creature_ids": [124, 126, 128, 132, 136] *
--         },
--         {
--           "creature_type": "Forgotten Beast",
--           "threat_level": 5,
--           "last_sighting_date": "0205-07-28",
--           "territory_proximity": 3.5,
--           "estimated_numbers": 1,
--           "creature_ids": [158]
--         }
--       ]
--     },
--     "vulnerability_analysis": [
--       {
--         "zone_id": 15, *
--         "zone_name": "Eastern Gate", *
--         "vulnerability_score": 0.68, * == crea_att.cas / ca.enemy_cas
--         "historical_breaches": 8, * == COUNT(DISTINCT attack_id)
--         "fortification_level": 2, * == l.fort_lev
--         "military_response_time": 48, * == AVG(creat_att.mil_res_time)
--         "defense_coverage": {
--           "structure_ids": [182, 183, 184], * == json_object(json_arrayarg(def_str_used))
--           "squad_ids": [401, 405] * == SQUAD_TRAINING.loc_id == l.loc_id
--         }
--       }
--     ],
--     "defense_effectiveness": [
--       {
--         "defense_type": "Drawbridge", * == l.zone_type
--         "effectiveness_rate": 95.12, * ==
--         "avg_enemy_casualties": 12.4, * == avg(ca.enemy_cas)
--         "structure_ids": [185, 186, 187, 188] *
--       },
--       {
--         "defense_type": "Trap Corridor",
--         "effectiveness_rate": 88.75,
--         "avg_enemy_casualties": 8.2,
--         "structure_ids": [201, 202, 203, 204]
--       }
--     ],
--     "military_readiness_assessment": [
--       {
--         "squad_id": 403,
--         "squad_name": "Crossbow Legends",
--         "readiness_score": 0.92,
--         "active_members": 7,
--         "avg_combat_skill": 8.6,
--         "combat_effectiveness": 0.85,
--         "response_coverage": [
--           {
--             "zone_id": 12,
--             "response_time": 0
--           },
--           {
--             "zone_id": 15,
--             "response_time": 36
--           }
--         ]
--       }
--     ],
--     "security_evolution": [
--       {
--         "year": 203,
--         "defense_success_rate": 68.42,
--         "total_attacks": 38,
--         "casualties": 42,
--         "year_over_year_improvement": 3.20
--       },
--       {
--         "year": 204,
--         "defense_success_rate": 72.50,
--         "total_attacks": 40,
--         "casualties": 36,
--         "year_over_year_improvement": 4.08
--       }
--     ]
--   }
-- }

WITH active_threats_stats AS (SELECT c.type,
                                     c.threat_level,
                                     cs.date                   last_sighting_date,
                                     COALESCE(SUM(ct.area), 0) creature_area,
                                     c.estimated_population    population,
                                     json_object(
                                             'creatures_ids', (SELECT json_arrayagg(cc.creature_id)
                                                               FROM creatures cc
                                                               WHERE cc.creature_id = c.creature_id)
                                     )
                              FROM creatures as c
                                       LEFT JOIN creature_sightings cs ON c.creature_id = cs.creature_id
                                  AND cs.date = (SELECT MAX(cs.date)
                                                 FROM creature_sightings
                                                 WHERE creature_id = c.creature_id)
                                       LEFT JOIN creature_territories ct ON ct.creature_id = c.creature_id
                              GROUP BY c.type, c.threat_level, c.estimated_population),
     vulnerability_stats AS (SELECT l.zone_id,
                                    l.name                                        zone_name,
                                    COALESCE(SUM(ca.casualities), 0)              total_casualties,
                                    COALESCE(SUM(ca.enemy_casualities), 0)        total_enemy_casualties,
                                    ROUND(AVG(ca.military_response_time_minutes)) avg_military_response_type
                             FROM locations l
                                      LEFT JOIN creature_attacks ca ON ca.location_id = l.location_id
                             GROUP BY l.zone_id, l.name, l.fortification_level),
     defense_effectivness_stats AS (SELECT l.zone_type,
                                           ROUND(
                                                   COALESCE(
                                                           SUM(ca.enemy_casualities)::numeric
                                                               / NULLIF(ca.casualities) * 100,
                                                           0), 2)    effectivness,
                                           AVG(ca.enemy_casualities) avg_enemy_cas
                                    FROM locations l
                                             LEFT JOIN creature_attacks ca ON ca.location_id = l.location_id
                                    GROUP BY l.zony_type),
     combat_skills AS (SELECT ds.dwarf_id, ds.skill_id, ds.level, ds.experience, ds.date
                       FROM dwarf_skills ds
                                LEFT JOIN skills s ON s.skill_id = ds.skill_id
                       WHERE s.category = 'combat'
                         AND ds.date = (SELECT MAX(date)
                                        FROM dwarf_skills
                                        GROUP BY dwarf_skills.dwarf_id, dwarf_skills.skill_id)),
     squad_stats AS (SELECT ms.squad_id,
                            ms.name,
                            SUM(CASE WHEN sm.exit_date IS NULL THEN 1 ELSE 0 END) active_members,
                            AVG(cs.experience)                                    avg_combat_skills
                     FROM military_squad ms
                              LEFT JOIN squad_members sm ON sm.squad_id = ms.squad_id
                              LEFT JOIN combat_skills cs ON cs.dwarf_id = sm.dwarf_id)
SELECT COALESCE(COUNT(DISTINCT ca.attack_id), 0)   total_recorded_attacks,
       COALESCE(COUNT(DISTINCT ca.creature_id), 0) unique_attackers

FROM creature_attacks ca
