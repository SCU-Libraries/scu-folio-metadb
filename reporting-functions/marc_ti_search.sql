--metadb:function marc_ti_search
DROP FUNCTION IF EXISTS marc_ti_search;

-- Output instance HRID values for records that match MARC tag, indicators, subfield, and 
-- field content. Sorted by field content then by instance
--'856' AS mtag,
--'4' AS ind1,
--'0' AS ind2,
--'u' AS subf,
--'ebsco' AS fcontent

CREATE OR REPLACE FUNCTION marc_ti_search (
--	mtag text DEFAULT '001',
--	ind1 text DEFAULT '',
--	ind2 text DEFAULT '',
--	subf text DEFAULT '',
--	fcontent text DEFAULT ''
	mtag text DEFAULT '856',
	ind1 text DEFAULT '4',
	ind2 text DEFAULT '0',
	subf text DEFAULT 'u',
	fcontent text DEFAULT 'ebsco'
)

RETURNS TABLE(
	instance_hrid text,
	marc_tag text,
	ind_1 text,
	ind_2 text,
	subfield text,
	f_content text
)

AS $$
WITH
	sparams AS (
		SELECT
			CASE
				WHEN (mtag !~* '^\d{3}$') THEN '001'
				ELSE mtag
			END AS mtag,
			CASE
				WHEN (ind1 !~* '^[ 0-9]$') THEN '*'
				ELSE ind1
			END AS ind1,
			CASE
				WHEN (ind2 !~* '^[ 0-9]$') THEN '*'
				ELSE ind2
			END AS ind2,
			CASE
				WHEN (lower(trim(subf)) !~* '^[0-9a-z]$') THEN '*'
				ELSE lower(trim(subf))
			END AS subf,
			CASE
				WHEN (lower(trim(fcontent)) !~* '^.+') THEN '*'
				ELSE lower(trim(fcontent))
			END AS fcontent
	)
	SELECT
		ins.jsonb->>'hrid' AS instance_hrid,
		mt.field AS marc_tag,
		mt.ind1 AS ind_1,
		mt.ind2 AS ind_2,
		mt.sf AS subfield,
		mt.content AS f_content
	FROM
		folio_source_record.marc__t mt
		LEFT JOIN folio_inventory.instance ins ON ins.id = mt.instance_id
		CROSS JOIN sparams
	WHERE
		ins.id IS NOT NULL AND
		mt.field ~* sparams.mtag AND
		mt.ind1 ~* sparams.ind1 AND
		mt.ind2 ~* sparams.ind2 AND
		mt.sf ~* sparams.subf AND
		mt.content ~* sparams.fcontent

$$
LANGUAGE sql
STABLE
PARALLEL SAFE;