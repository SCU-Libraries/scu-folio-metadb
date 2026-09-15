--metadb:function course_term_dates_circ_stats
DROP FUNCTION IF EXISTS course_term_dates_circ_stats;

-- Output circ counts (checkouts + renewals) for all items attached to courses assigned
-- to courselistings for a given term. Optional user-supplied dates for permanent term
-- reserves only.Sorted by course number, name, item start date, item title, item 
-- effective or copied call number. All null values should be replaced by empty values.

CREATE OR REPLACE FUNCTION course_term_dates_circ_stats (
	term_name text DEFAULT 'permanent', -- expects exact term name from folio like "2026 Winter Quarter" or UUID
	date_one date DEFAULT '2000-01-01',
	date_two date DEFAULT '2099-12-31'
)

RETURNS TABLE(
	date_one date,
	date_two date,
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
	udts AS (
		SELECT
			CASE
				WHEN (lower(trim(term_name)) !~* '(permanent|f6e514e1-2155-4f82-9fd7-6397e68620f0)' OR date_one >= date(CURRENT_TIMESTAMP AT TIME ZONE 'US/Pacific') OR date_one >= date_two) THEN '2000-01-01'
				ELSE date_one
			END AS date_one,
			CASE
				WHEN (lower(trim(term_name)) !~* '(permanent|f6e514e1-2155-4f82-9fd7-6397e68620f0)' OR date_two <= date_one) THEN '2099-12-31'
				ELSE date_two
			END AS date_two
	),
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
		CROSS JOIN udts
		LEFT JOIN
			crss ON crss.clid = crr.courselistingid::TEXT
		LEFT JOIN LATERAL
			(SELECT DISTINCT ON (id, courselistingid)
				id,
				__start,
				courselistingid
			FROM
				folio_courses.coursereserves_reserves__
			ORDER BY
				id, courselistingid, __start ASC) sdate ON sdate.id = crr.id
		LEFT JOIN
			(SELECT DISTINCT ON (id, courselistingid)
				id,
				__end,
				courselistingid
			FROM
				folio_courses.coursereserves_reserves__
			ORDER BY
				id, courselistingid, __end DESC) edate ON edate.id = crr.id
		LEFT JOIN folio_inventory.item i ON i.id = (crr.jsonb->>'itemId')::UUID
		WHERE
			crss.clid IS NOT NULL
			AND date(sdate.__start::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') <= udts.date_two
			AND date(edate.__end::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') >= udts.date_one
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
		CROSS JOIN udts
		LEFT JOIN crr_items ON crr_items.item_id = ln.jsonb->>'itemId'
		WHERE
			ln.jsonb->>'action' ~* '^(checkedout|checkedOutThroughOverride|renewed|renewedThroughOverride)$' AND
			date((ln.creation_date)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') BETWEEN crr_items.crr_start AND crr_items.crr_end AND
			date((ln.creation_date)::TIMESTAMPTZ AT TIME ZONE 'US/Pacific') BETWEEN udts.date_one AND udts.date_two
		GROUP BY
			ln_itemId, item_barcode, crr_items.clid
	)
	SELECT DISTINCT ON (course_number, course_name, item_title, call_number, course_listing_id, course_id, item_id)
		udts.date_one,
		udts.date_two,
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
	CROSS JOIN udts
	LEFT JOIN
		lns ON lns.ln_itemId = crr_items.item_id AND lns.ln_clid = crr_items.clid
	LEFT JOIN
		cls ON cls.course_listing_id = crr_items.clid
	LEFT JOIN
		crss ON crss.clid = cls.course_listing_id
	LEFT JOIN
		trms ON trms.term_id = cls.cltid
	ORDER BY
		course_number, course_name, item_title, call_number, course_listing_id, course_id, item_id, crr_items.crr_end DESC

$$
LANGUAGE sql
STABLE
PARALLEL SAFE;
