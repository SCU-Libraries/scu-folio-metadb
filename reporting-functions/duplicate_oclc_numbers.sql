--metadb:function duplicate_oclc_numbers

DROP FUNCTION IF EXISTS duplicate_oclc_numbers;
	
CREATE FUNCTION duplicate_oclc_numbers (
)
returns table(
	dup_count numeric,
	id_type text,
	OCLC_number text
)
as $$
SELECT
	count(id) AS dup_count,
	id_type,
	OCLC_number
FROM (SELECT DISTINCT
		id,
		jsonb_extract_path_text(jsonb_array_elements(jsonb_extract_path(jsonb, 'identifiers')),'identifierTypeId') AS id_type,
		jsonb_extract_path_text(jsonb_array_elements(jsonb_extract_path(jsonb, 'identifiers')),'value') AS OCLC_number
	FROM
		folio_inventory.instance
	WHERE
		(jsonb->>'staffSuppress' IS NULL OR
		jsonb->>'staffSuppress' = 'false') AND
		jsonb->>'statisticalCodeIds' !~* '"2125acda-b369-4388-9587-33dbc3398cbe"') ins
WHERE
	id_type = '439bfbae-75bc-4f74-9fc7-b2a2d47ce3ef'
GROUP BY
	id_type, OCLC_number
HAVING
	count(id) > 1
ORDER BY
	dup_count DESC, OCLC_number
$$
language sql
STABLE 
PARALLEL SAFE; 
