--metadb:function circ_stats_course_reserves

DROP FUNCTION IF EXISTS circ_stats_course_reserves;
	
CREATE FUNCTION circ_stats_course_reserves(
	Circ_Stat_Course_Name text,
	start_date date DEFAULT '2000-01-01',
  	end_date date DEFAULT '2099-01-01'
)
returns table(
	item_barcode text,
	instance_title text,
	circ_count numeric
)
as $$
SELECT 
	iext.barcode as item_barcode, 
	inst.title as instance_title, 
	lit.clid as circ_count
from
	folio_courses.coursereserves_courses__t__ crct
	left join folio_courses.coursereserves_reserves__t__ crrt on crct.course_listing_id = crrt.course_listing_id
	left join folio_derived.item_ext iext on crrt.item_id = iext.item_id
	LEFT JOIN folio_derived.holdings_ext hrt on iext.holdings_record_id = hrt.holdings_id
	LEFT JOIN folio_derived.instance_ext inst on hrt.instance_id = inst.instance_id
	left join 
		(SELECT 
			count(loan_id) AS clid,
			item_id
		FROM folio_derived.loans_items
		WHERE
			start_date <= date(loan_date) AND
			date(loan_date) <= end_date
		GROUP BY
			item_id) lit ON lit.item_id = crrt.item_id
WHERE
	crct.name ~* Circ_Stat_Course_Name  AND
	lit.clid >= 1 
group by
	iext.barcode, inst.title, lit.clid
ORDER BY
	instance_title 
$$
language sql
STABLE 
PARALLEL SAFE; 
