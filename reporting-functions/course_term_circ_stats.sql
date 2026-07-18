--metadb:function course_term_circ_stats
DROP FUNCTION IF EXISTS course_term_circ_stats;

-- Output circ counts (checkouts + renewals) for all items attached to courses assigned
-- to courselistings for a given term. If no term is supplied, defaults to the "Permanent"
-- term. Sorted by course number, name, item start date, item title, item call number.
-- All null values should be replaced by empty values.

CREATE OR REPLACE FUNCTION course_term_circ_stats (
	term_name text DEFAULT ''  -- expects exact term name from folio like "2026 Winter Quarter" or UUID
)

RETURNS TABLE(
	course_term text,
	course_department text,
	course_number text,
	course_name text,
	primary_instructor text,
	checkout_count bigint,
	item_title text,
	call_number text,
	item_barcode text,
	course_item_start date,
	course_item_end date,
	course_listing_id text,
	course_id text,
	item_id text
)

AS $$
WITH
	trms AS (
		SELECT
			trm.id::TEXT AS term_id,
			trm.jsonb->>'name' AS course_term
		FROM
			folio_courses.coursereserves_terms trm
		WHERE
			lower(trim(trm.jsonb->>'name')) = lower(trim(term_name)) OR
			lower(trim(trm.id::TEXT)) = lower(trim(term_name))
	),
	cls AS (
		SELECT
			DISTINCT ON (cl.id)
			cl.id::TEXT AS course_listing_id,
			coalesce(primary_instructors.primary_instructor_name, '') AS primary_instructor,
			cl.jsonb->>'termId' AS cltid,
			date((__start)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') AS cls_start,
			date((__end)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') AS cls_end
		FROM
			folio_courses.coursereserves_courselistings__ cl
		LEFT JOIN
			trms ON trms.term_id = cl.jsonb->>'termId'
		LEFT JOIN LATERAL (
			SELECT
				(jsonb_path_query(cl.jsonb, '$.instructorObjects[0]')) ->> 'name' AS primary_instructor_name
			FROM
				folio_courses.coursereserves_courselistings__ clpi
			WHERE
				clpi.__id = cl.__id
		) primary_instructors ON true
		WHERE
			trms.term_id IS NOT NULL
		ORDER BY
			cl.id, cl.__start DESC
	),
	crss AS (
		SELECT
			DISTINCT ON (crs.id)
			crs.id AS course_id,
			crs.jsonb->>'name' AS course_name,
			coalesce(crs.jsonb->>'courseNumber', '') AS course_number,
			crs.jsonb->>'courseListingId' AS clid,
			coalesce(crd.jsonb->>'name', '') AS course_department,
			cls.cls_start,
			cls.cls_end
		FROM
			folio_courses.coursereserves_courses__ crs
		LEFT JOIN
			cls ON cls.course_listing_id = crs.jsonb->>'courseListingId'
		LEFT JOIN
			folio_courses.coursereserves_departments crd ON crd.id::TEXT = crs.jsonb->>'departmentId'
		WHERE
			cls.course_listing_id IS NOT NULL
		ORDER BY
			crs.id, crs.__start DESC
	),
	crr_items AS (
		SELECT DISTINCT ON (crr.id, crr.courselistingid)
			crr.id,
			(crr.courselistingid)::TEXT AS clid,
			CASE
				WHEN crss.cls_start > date((sdate.__start)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') THEN crss.cls_start
				ELSE date((sdate.__start)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific')
			END AS crr_start,
			CASE
				WHEN crss.cls_end < date((edate.__end)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') THEN crss.cls_end
				ELSE date((edate.__end)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific')
			END AS crr_end,
			date((sdate.__start)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') AS crr_istart,
			date((edate.__end)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') AS crr_iend,
			left(crr.jsonb#>>'{copiedItem,title}', 80) AS item_title,
			crr.jsonb#>>'{copiedItem,barcode}' AS item_barcode,
			crr.jsonb->>'itemId' AS item_id,
			crr.courselistingid AS item_clid,
			sdate.__start AS crr_stime,
			edate.__end AS crr_etime,
			CASE
				WHEN i.jsonb#>>'{effectiveCallNumberComponents,callNumber}' IS NULL THEN crr.jsonb#>>'{copiedItem,callNumber}'
				ELSE 
					trim(both from concat(i.jsonb#>>'{effectiveCallNumberComponents,prefix}', ' ',
					i.jsonb#>>'{effectiveCallNumberComponents,callNumber}',
					CASE
						WHEN i.jsonb->>'volume' IS NOT NULL THEN concat(' ',i.jsonb->>'volume')
					END, 
					CASE 
						WHEN i.jsonb->>'copyNumber' != '1' THEN concat(' c.', i.jsonb->>'copyNumber')
					END
				)) 
			END AS call_number
		FROM
			folio_courses.coursereserves_reserves__ crr
		LEFT JOIN
			crss ON crss.clid = crr.courselistingid::TEXT
		LEFT JOIN LATERAL
			(SELECT DISTINCT ON (id)
				id,
				__start
			FROM
				folio_courses.coursereserves_reserves__
			ORDER BY
				id, __start ASC) sdate ON sdate.id = crr.id
		LEFT JOIN
			(SELECT DISTINCT ON (id)
				id,
				__end,
				courselistingid
			FROM
				folio_courses.coursereserves_reserves__
			ORDER BY
				id, __end DESC) edate ON edate.id = crr.id
		LEFT JOIN folio_inventory.item i ON i.id = (crr.jsonb->>'itemId')::UUID
		WHERE
			crss.clid IS NOT NULL
		ORDER BY
			crr.id, crr.courselistingid, crr.__start DESC
	),
	lns AS (
		SELECT
			COUNT(ln.id) AS ln_count,
			ln.jsonb->>'itemId' AS ln_itemId,
			item_barcode,
			crr_items.clid AS ln_clid
		FROM
			folio_circulation.loan__ ln
		LEFT JOIN crr_items ON crr_items.item_id = ln.jsonb->>'itemId'
		WHERE
			ln.jsonb->>'action' ~* '^(checkedout|checkedOutThroughOverride|renewed|renewedThroughOverride)$' AND
			date((ln.creation_date)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') BETWEEN crr_items.crr_start AND crr_items.crr_end
		GROUP BY
			ln_itemId, item_barcode, crr_items.clid
	)
	SELECT
		trms.course_term,
		crss.course_department,
		crss.course_number,
		crss.course_name,
		cls.primary_instructor,
		coalesce(lns.ln_count, 0) AS checkout_count,
		crr_items.item_title,
		crr_items.call_number,
		crr_items.item_barcode,
		crr_items.crr_start AS course_item_start,
		crr_items.crr_end AS course_item_end,
		cls.course_listing_id,
		crss.course_id,
		crr_items.item_id
	FROM
		crr_items
	LEFT JOIN
		lns ON lns.ln_itemId = crr_items.item_id AND lns.ln_clid = crr_items.clid
	LEFT JOIN
		cls ON cls.course_listing_id = crr_items.clid
	LEFT JOIN
		crss ON crss.clid = cls.course_listing_id
	LEFT JOIN
		trms ON trms.term_id = cls.cltid
	ORDER BY
		course_number, course_name, crr_items.crr_end, item_title, call_number

$$
LANGUAGE sql
STABLE
PARALLEL SAFE;

--		cls.cls_start,
--		crr_items.crr_istart,
--		cls.cls_end,
--		crr_items.crr_iend,
--			lower(trim(trm.jsonb->>'name')) = lower(trim('2026 Winter Quarter'))
