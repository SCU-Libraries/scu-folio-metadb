--metadb:function _reserves_quarter

DROP FUNCTION IF EXISTS _reserves_quarter;

CREATE FUNCTION _reserves_quarter(
    term_name  text DEFAULT NULL,
    start_date date DEFAULT '0001-01-01',
    end_date   date DEFAULT '9999-12-31',
    exclusions text DEFAULT NULL
)
RETURNS TABLE(
    course_term        text,
    course_number      text,
    item_barcode       text,
    call_number        text,
    instance_title     text,
    checkout_count     bigint,
    course_listing_id  text,
    item_id            text
)
AS $$
WITH
    -- Resolve the effective date window.
    -- If term_name is provided, look up that term's start/end dates.
    -- Otherwise fall through to the caller-supplied start_date/end_date.
    resolved_window AS (
        SELECT
            CASE
                WHEN trim(term_name) IS NOT NULL AND trim(term_name) <> ''
                THEN t.start_date
                ELSE start_date
            END AS win_start,
            CASE
                WHEN trim(term_name) IS NOT NULL AND trim(term_name) <> ''
                THEN t.end_date
                ELSE end_date
            END AS win_end
        FROM (SELECT 1) dummy
        LEFT JOIN folio_courses.coursereserves_terms__t__ t
               ON trim(term_name) IS NOT NULL
              AND trim(term_name) <> ''
              AND t.name = term_name
        LIMIT 1
    )
SELECT
    term_resolved.name   AS course_term,
    courses.course_number,
    iext.barcode         AS item_barcode,
    iext.effective_call_number AS call_number,
    inst.title           AS instance_title,
    COUNT(li.__id)       AS checkout_count,
    courses.course_listing_id,
    reserves.item_id
FROM
    folio_courses.coursereserves_courses__t__ courses
INNER JOIN folio_courses.coursereserves_reserves__t__ reserves
        ON courses.course_listing_id = reserves.course_listing_id
-- Resolve the display term name for this course listing (same lateral as original).
LEFT JOIN LATERAL (
        SELECT t.name
        FROM folio_courses.coursereserves_courses__t__ c_same
        INNER JOIN folio_courses.coursereserves_courselistings__t__ l_same
                ON c_same.course_listing_id = l_same.id
        INNER JOIN folio_courses.coursereserves_terms__t__ t
                ON l_same.term_id = t.id
        WHERE c_same.course_number = courses.course_number
          AND (
              l_same.id = courses.course_listing_id
              OR c_same.course_listing_id <> courses.course_listing_id
          )
          -- When term_name is set, only consider listings under that term.
          AND (
              term_name IS NULL OR term_name = ''
              OR t.name = term_name
          )
        ORDER BY
            CASE WHEN l_same.id = courses.course_listing_id THEN 0 ELSE 1 END,
            t.start_date DESC
        LIMIT 1
) term_resolved ON true
LEFT JOIN folio_derived.item_ext iext
       ON reserves.item_id = iext.item_id
LEFT JOIN folio_derived.holdings_ext hrt
       ON iext.holdings_record_id = hrt.holdings_id
LEFT JOIN folio_derived.instance_ext inst
       ON hrt.instance_id = inst.instance_id
-- Only count checkouts that fall within the resolved quarter window.
LEFT JOIN folio_circulation.loan__t__ li
       ON iext.item_id = li.item_id
      AND li.action = 'checkedout'
      AND li.loan_date BETWEEN (SELECT win_start FROM resolved_window)
                           AND (SELECT win_end   FROM resolved_window)
WHERE
    reserves.item_id IS NOT NULL
    -- Current reserves only; no historical toggle on this report.
    AND reserves.__current = true
    -- term_resolved must match when term_name is provided.
    AND (
        term_name IS NULL OR term_name = ''
        OR term_resolved.name IS NOT NULL
    )
    -- Exclusions: remove specific course numbers when flag is present.
    AND (
        exclusions IS NULL OR (
            (exclusions NOT ILIKE '%POP%'   OR courses.course_number IS DISTINCT FROM 'POP') AND
            (exclusions NOT ILIKE '%LAW%'   OR courses.course_number NOT ILIKE 'LAW%') AND
            (exclusions NOT ILIKE '%NEW%'   OR courses.course_number IS DISTINCT FROM 'NEW') AND
            (exclusions NOT ILIKE '%EMPTY%' OR (courses.course_number IS NOT NULL AND courses.course_number <> ''))
        )
    )
GROUP BY
    courses.course_listing_id,
    courses.course_number,
    reserves.item_id,
    iext.barcode,
    iext.effective_call_number,
    inst.title,
    term_resolved.name
ORDER BY
    course_term
$$
LANGUAGE sql
STABLE
PARALLEL SAFE;