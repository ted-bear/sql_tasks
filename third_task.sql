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
FROM Dwarves AS d
