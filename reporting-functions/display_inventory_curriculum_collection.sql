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

SELECT distinct  
	lt.name as "Location", 
	int.index_title as "Title", 
	ic.contributor_name as "Author", 
	concat('Curr ', hrt.call_number) as "Call Number", 
	it.volume as "Volume", 
	it.copy_number as "Copy Number", 
	case 
		when int.hrid like 'b%' then concat('https://libcat.scu.edu/Record/', left(int.hrid, 8))
		else concat('https://libcat.scu.edu/Record/', int.hrid)
	end as "Link",
	it.barcode as "Barcode", 
	it.id as "Item ID", 
	it.holdings_record_id as "Holdings ID"
FROM 
	folio_inventory.item__t as it
	left join folio_inventory.holdings_record__t as hrt on it.holdings_record_id = hrt.id
	left join folio_inventory.location__t as lt on it.effective_location_id = lt.id
	left join folio_inventory.instance__t as int on hrt.instance_id = int.id
	left join folio_derived.instance_contributors as ic on int.id = ic.instance_id
where 
	hrt.call_number_prefix = 'Curr'
	and ic.contributor_is_primary = TRUE;
