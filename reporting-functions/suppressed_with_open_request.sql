--metadb:function suppressed_with_open_request
DROP FUNCTION IF EXISTS suppressed_with_open_request;

-- Output instance and/or item HRID values for suppressed records with open requests
-- "Permanent" term. Sorted by course name, number, item start date, item title,
-- item call number. All null values should be replaced by empty values.

CREATE OR REPLACE FUNCTION suppressed_with_open_request (
)

RETURNS TABLE(
	request_id text,
	request_type text,
	course_number text,
	instance_hrid text,
	item_hrid text,
	instance_supp text,
	instance_staff_supp text,
	holding_supp text,
	item_supp text
)

AS $$
SELECT
	fc_r.id AS request_id,
	fc_r.jsonb->>'requestLevel' AS request_type,
	coalesce(fi_in.jsonb->>'hrid', fi_in1.jsonb->>'hrid') AS instance_hrid,
	coalesce(fi_it.jsonb->>'hrid', '') AS item_hrid,
	coalesce(fi_in.jsonb->>'discoverySuppress', fi_in1.jsonb->>'discoverySuppress') AS instance_supp,
	coalesce(fi_in.jsonb->>'staffSuppress', fi_in1.jsonb->>'staffSuppress') AS instance_staff_supp,
	coalesce(fi_hr.jsonb->>'discoverySuppress', '') AS holding_supp,
	coalesce(fi_it.jsonb->>'discoverySuppress', '') AS item_supp
FROM
	folio_circulation.request fc_r
LEFT JOIN folio_inventory.instance fi_in ON fi_in.id = (fc_r.jsonb->>'instanceId')::UUID
LEFT JOIN folio_inventory.item fi_it ON fi_it.id = (fc_r.jsonb->>'itemId')::UUID
LEFT JOIN folio_inventory.holdings_record fi_hr ON fi_hr.id = fi_it.holdingsrecordid
LEFT JOIN folio_inventory.instance fi_in1 ON fi_in1.id = fi_hr.instanceid
WHERE
	(fi_in.id IS NOT NULL AND fi_it.id IS NULL
	AND fi_in.jsonb->>'source' != 'INN-Reach'
	AND (fi_in.jsonb->>'discoverySuppress' = 'true'
	OR fi_in.jsonb->>'staffSuppress' = 'true')
	AND fc_r.jsonb->>'status' ~* '^open')
	OR
	(fi_it.id IS NOT NULL
	AND fi_in1.jsonb->>'source' != 'INN-Reach'
	AND (fi_it.jsonb->>'discoverySuppress' = 'true'
	OR fi_hr.jsonb->>'discoverySuppress' = 'true'
	OR fi_in1.jsonb->>'discoverySuppress' = 'true'
	OR fi_in1.jsonb->>'staffSuppress' = 'true')
	AND fc_r.jsonb->>'status' ~* '^open')
ORDER BY
	reqType, instancehrid, itemhrid

$$
LANGUAGE sql
STABLE
PARALLEL SAFE;
