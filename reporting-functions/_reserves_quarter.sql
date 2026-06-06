--metadb:function _reserves_quarter

DROP FUNCTION IF EXISTS _reserves_quarter;

CREATE FUNCTION _reserves_quarter(
    term_name       text DEFAULT NULL,
    start_date      date DEFAULT '0001-01-01',
    end_date        date DEFAULT '9999-12-31',
    exclusions      text DEFAULT NULL,
    show_historical text DEFAULT NULL,  -- '1','true','t','yes','y','on' = include non-current reserves
    course_number   text DEFAULT NULL
)
RETURNS TABLE(
    course_term        text,
    course_number      text,
    item_barcode       text,
    call_number        text,
    instance_title     text,
    checkout_count     bigint,
    course_listing_id  text,
    item_id            text,
    win_start          date,
    win_end            date
)
AS $$
WITH
    resolved_window AS (
        SELECT
            CASE
                WHEN trim(term_name) IS NOT NULL AND trim(term_name) <> ''
                THEN t.start_date
                ELSE $2
            END AS win_start,
            CASE
                WHEN trim(term_name) IS NOT NULL AND trim(term_name) <> ''
                THEN t.end_date
                ELSE $3
            END AS win_end
        FROM (SELECT 1) dummy
        LEFT JOIN folio_courses.coursereserves_terms__t__ t
               ON trim(term_name) IS NOT NULL
              AND trim(term_name) <> ''
              AND t.name = term_name
        LIMIT 1
    )
SELECT
    CASE
        WHEN term_resolved.name = 'Permanent' AND trim(term_name) IS NOT NULL AND trim(term_name) <> ''
        THEN term_name || ', Permanent'
        ELSE term_resolved.name
    END                            AS course_term,
    courses.course_number,
    iext.barcode                   AS item_barcode,
    iext.effective_call_number     AS call_number,
    inst.title                     AS instance_title,
    COUNT(ci.id)                   AS checkout_count,
    courses.course_listing_id,
    reserves.item_id,
    (SELECT win_start FROM resolved_window) AS win_start,
    (SELECT win_end   FROM resolved_window) AS win_end
FROM
    folio_courses.coursereserves_courses__t__ courses
INNER JOIN folio_courses.coursereserves_reserves__t__ reserves
        ON courses.course_listing_id = reserves.course_listing_id
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
          AND (
              term_name IS NULL OR term_name = ''
              OR t.name = term_name
              OR t.name = 'Permanent'
          )
        ORDER BY
            CASE WHEN l_same.id = courses.course_listing_id THEN 0 ELSE 1 END,
            CASE WHEN t.name = term_name THEN 0 ELSE 1 END,
            t.start_date DESC
        LIMIT 1
) term_resolved ON true
LEFT JOIN folio_derived.item_ext iext
       ON reserves.item_id = iext.item_id
LEFT JOIN folio_derived.holdings_ext hrt
       ON iext.holdings_record_id = hrt.holdings_id
LEFT JOIN folio_derived.instance_ext inst
       ON hrt.instance_id = inst.instance_id
-- Replaced loan__t__ with check_in__t__ to count completed checkouts per term window
LEFT JOIN folio_circulation.check_in__t__ ci
       ON iext.item_id = ci.item_id
      AND ci.item_status_prior_to_check_in = 'Checked out'
      AND ci.occurred_date_time BETWEEN (SELECT win_start FROM resolved_window)
                                    AND (SELECT win_end   FROM resolved_window)
WHERE
    reserves.item_id IS NOT NULL
    AND (
        lower(coalesce(trim(show_historical), '')) IN ('1','true','t','yes','y','on')
        OR reserves.__current = true
    )
    AND (
        term_name IS NULL OR term_name = ''
        OR term_resolved.name IS NOT NULL
    )
    -- Course number filter
    AND (
        $6 IS NULL OR trim($6) = ''
        OR courses.course_number ILIKE $6 || '%'
    )
    -- Exclusions
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
    term_resolved.name,
    win_start,
    win_end
ORDER BY
    course_term
$$
LANGUAGE sql
STABLE
PARALLEL SAFE;