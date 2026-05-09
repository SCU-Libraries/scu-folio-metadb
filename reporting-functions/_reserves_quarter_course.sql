-- =============================================================================
-- COURSE RESERVES REPORT FUNCTIONS
-- =============================================================================
-- Permanent = reserves.end_date IS NULL
-- Historical (quarter course report) = all past reserve instances for a
--   course+item, each row scoped to its own term's checkout date range.
-- Term resolution: term_name takes priority over explicit start_date/end_date.
--   If term_name is provided, dates are resolved from coursereserves_terms__t__.
-- Exclusions apply to all reports.
-- =============================================================================

-- =============================================================================
-- 2. SINGLE QUARTER COURSE REPORT
--    One or more specific courses, checkouts scoped to a quarter.
--    Historical toggle: when ON, shows all past reserve instances for the
--    course+item, each row's checkout count scoped to that instance's own
--    term date range (not the caller's quarter). When OFF, current only.
-- =============================================================================

DROP FUNCTION IF EXISTS course_reserves_quarter_course_report;

CREATE FUNCTION course_reserves_quarter_course_report(
    course_codes      text DEFAULT NULL,  -- comma-separated, e.g. 'CS 101,HIST 200'
    term_name         text DEFAULT NULL,
    start_date        date DEFAULT '0001-01-01',
    end_date          date DEFAULT '9999-12-31',
    exclusions        text DEFAULT NULL,
    show_historical   text DEFAULT NULL   -- '1','true','t','yes','y','on' = show all past instances
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
WITH
    -- Resolve the caller's quarter window for anchoring the course lookup.
    -- When show_historical is ON, each reserve instance uses its own term's
    -- dates (resolved per-row in the main query via the term lateral).
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
-- Resolve the display term name AND that term's date window per reserve instance.
-- For historical rows, this lateral returns the term belonging to each listing,
-- which is then used to scope that row's checkout count.
LEFT JOIN LATERAL (
        SELECT t.name, t.start_date AS term_start, t.end_date AS term_end
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
          -- When not showing historical, restrict lateral to the caller's term.
          AND (
              lower(coalesce(trim(show_historical), '')) IN ('1','true','t','yes','y','on')
              OR term_name IS NULL OR term_name = ''
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
-- Checkout counts are scoped to each reserve instance's own term date window.
-- For current (non-historical) rows this is the caller's resolved quarter.
-- For historical rows this is that instance's resolved term dates.
LEFT JOIN folio_circulation.loan__t__ li
       ON iext.item_id = li.item_id
      AND li.action = 'checkedout'
      AND li.loan_date BETWEEN
              coalesce(term_resolved.term_start, (SELECT win_start FROM resolved_window))
          AND coalesce(term_resolved.term_end,   (SELECT win_end   FROM resolved_window))
WHERE
    reserves.item_id IS NOT NULL
    -- Historical toggle: when OFF, only current reserves.
    AND (
        lower(coalesce(trim(show_historical), '')) IN ('1','true','t','yes','y','on')
        OR reserves.__current = true
    )
    -- term_resolved must resolve when term_name is provided.
    AND (
        term_name IS NULL OR term_name = ''
        OR term_resolved.name IS NOT NULL
    )
    -- Filter to the specified course code(s).
    -- Normalizes spacing between letters and digits (e.g. 'CS101' → 'CS 101').
    AND (
        course_codes IS NULL OR course_codes = ''
        OR regexp_replace(upper(trim(courses.course_number)), '([A-Z])(\d)', '\1 \2', 'g') = ANY(
            string_to_array(
                regexp_replace(
                    regexp_replace(upper(trim(course_codes)), '([A-Z])(\d)', '\1 \2', 'g'),
                    '\s*,\s*', ',', 'g'
                ),
                ','
            )
        )
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
    term_resolved.name,
    term_resolved.term_start,
    term_resolved.term_end
ORDER BY
    course_term
$$
LANGUAGE sql
STABLE
PARALLEL SAFE;