--metadb:function circ_stats_course_reserves_all

DROP FUNCTION IF EXISTS circ_stats_course_reserves_all;

CREATE FUNCTION circ_stats_course_reserves_all(
    start_date date DEFAULT '1900-01-01',
    end_date   date DEFAULT '2099-01-01'
)
RETURNS TABLE(
    item_barcode text,
    instance_title text,
    circ_count numeric
)
AS $$
SELECT 
    iext.barcode AS item_barcode,
    inst.title AS instance_title,
    COALESCE(lit.clid, 0) AS circ_count
FROM
    folio_courses.coursereserves_courses__t__ crct
LEFT JOIN folio_courses.coursereserves_reserves__t__ crrt
       ON crct.course_listing_id = crrt.course_listing_id
LEFT JOIN folio_derived.item_ext iext
       ON crrt.item_id = iext.item_id
LEFT JOIN folio_derived.holdings_ext hrt
       ON iext.holdings_record_id = hrt.holdings_id
LEFT JOIN folio_derived.instance_ext inst
       ON hrt.instance_id = inst.instance_id
LEFT JOIN (
        SELECT 
            item_id,
            COUNT(loan_id) AS clid
        FROM folio_derived.loans_items
        WHERE 
            date(loan_date) >= start_date
            AND date(loan_date) <= end_date
        GROUP BY item_id
) lit
       ON lit.item_id = crrt.item_id
WHERE 
    crrt.item_id IS NOT NULL  
GROUP BY 
    iext.barcode, inst.title, lit.clid
$$
LANGUAGE sql
STABLE
PARALLEL SAFE;

