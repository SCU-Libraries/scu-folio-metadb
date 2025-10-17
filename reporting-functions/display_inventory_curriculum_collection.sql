--metadb:function display_inventory_curriculum_collection

DROP FUNCTION IF EXISTS display_inventory_curriculum_collection;
	
CREATE FUNCTION display_inventory_curriculum_collection(
	call_number_prefix text
)
returns table(
	location text,
	index_title text,
	contributor_name text,
	call_number text,
	volume text,
	copy_number text,
	link text,
	item_barcode text,
	item_id text,
	holdings_id text
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

$$
language sql
STABLE 
PARALLEL SAFE; 
