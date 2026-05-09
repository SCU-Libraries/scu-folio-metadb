--metadb:function _reserves_permanent

DROP FUNCTION IF EXISTS _reserves_permanent;

CREATE FUNCTION _reserves_permanent(
    start_date      date DEFAULT '0001-01-01',
    end_date        date DEFAULT '9999-12-31',
    exclusions      text DEFAULT NULL,
    show_historical text DEFAULT NULL   -- '1','true','t','yes','y','on' = include non-current
)
RETURNS TABLE(
    course_term        text,
    course_number      text,
    item_barcode       text,
    call_number        text,
    instance_title     text,
    checkout_count     bigint,
    is_current         integer,
    course_listing_id  text,
    item_id            text,
    reserves_start_date date,
    reserves_end_date   date
)
AS $$
SELECT
    term_resolved.name        AS course_term,
    courses.course_number,
    iext.barcode              AS item_barcode,
    iext.effective_call_number AS call_number,
    inst.title                AS instance_title,
    COUNT(li.__id)            AS checkout_count,
    CASE WHEN reserves.__current THEN 1 ELSE 0 END AS is_current,
    courses.course_listing_id,
    reserves.item_id,
    reserves.start_date       AS reserves_start_date,
    reserves.end_date         AS reserves_end_date
FROM
    folio_courses.coursereserves_courses__t__ courses
INNER JOIN folio_courses.coursereserves_reserves__t__ reserves
        ON courses.course_listing_id = reserves.course_listing_id
-- Resolve display term name (no term_name filter; this report is not quarter-scoped).
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
-- Checkout counts scoped to caller's date range.
LEFT JOIN folio_circulation.loan__t__ li
       ON iext.item_id = li.item_id
      AND li.action = 'checkedout'
      AND li.loan_date BETWEEN start_date AND end_date
WHERE
    reserves.item_id IS NOT NULL
    -- Permanent reserves only: no end date.
    AND reserves.end_date IS NULL
    -- Historical toggle: when OFF, only current reserves.
    AND (
        lower(coalesce(trim(show_historical), '')) IN ('1','true','t','yes','y','on')
        OR reserves.__current = true
    )
    -- Exclusions.
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
    reserves.start_date,
    reserves.end_date,
    iext.barcode,
    iext.effective_call_number,
    inst.title,
    reserves.__current,
    term_resolved.name
ORDER BY
    course_term
$$
LANGUAGE sql
STABLE
PARALLEL SAFE;