--metadb:function search_notes

DROP FUNCTION IF EXISTS search_notes;
	
CREATE FUNCTION search_notes(
	note_string text
)
returns table(
  item_uuid text,
	item_barcode text,
	instance_title_publisher_date text,
	holdings_location_call_number text,
	item_notes text
)
as $$

SELECT DISTINCT
	ihi.item_id as "Item UUID", 
	ihi.barcode as "Barcode", 
	concat(ihi.title, ', ', ip.publisher, ', ', ip.date_of_publication) as "Instance (Title, Publisher, Date)",
	concat(he.permanent_location_name, ', ', he.call_number) as "Holdings (Location, Call number)", 
	string_agg(fdin.note, ', ') as "Item notes"
FROM
	folio_derived.items_holdings_instances as ihi
	left join folio_derived.item_notes as fdin on ihi.item_id = fdin.item_id 
	left join folio_derived.instance_contributors as ic on ihi.instance_id = ic.instance_id
	left join folio_derived.holdings_ext as he on ihi.holdings_id = he.holdings_id 
	left join folio_derived.instance_publication as ip on ihi.instance_id = ip.instance_id 
WHERE
	fdin.note ~* note_string
GROUP BY
	ihi.item_id, ihi.barcode, ihi.title, ip.publisher, ip.date_of_publication, he.permanent_location_name, he.call_number
	
$$
language sql
STABLE 
PARALLEL SAFE; 
