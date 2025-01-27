--metadb:function class_list

DROP FUNCTION IF EXISTS class_list;
	
CREATE FUNCTION class_list(
	note_string text
)
returns table(
	item_barcode,
	item_shelving_location_code text,
	item_shelving_location_name text,
	call_number text,
	instance_title text,
	item_note text
)
as $$
	
select distinct 
	i.jsonb ->> 'barcode' as item_barcode, 
	lt.code,
	lt.name,
	concat_ws(' ', i.jsonb -> 'effectiveCallNumberComponents'->>'prefix', i.jsonb -> 'effectiveCallNumberComponents'->>'callNumber', i.jsonb ->> 'copyNumber') as item_callnumber,
	inst.title,
	jsonb_extract_path_text(notes.data, 'note') as Note
from folio_inventory.item__ as i
cross join lateral jsonb_array_elements(jsonb_extract_path(i.jsonb, 'notes')) with ordinality as notes (data)
left join folio_inventory.item__t__ as it on i.id = it.id
left join folio_inventory.holdings_record__t__ as hrt on it.holdings_record_id = hrt.id
left join folio_inventory.instance__t__ as inst on hrt.instance_id = inst.id
left join folio_inventory.location__t__ as lt on hrt.effective_location_id = lt.id
left join folio_derived.instance_contributors as ic on inst.id = ic.instance_id

where jsonb_extract_path_text(notes.data, 'note') like note_string

$$
language sql
STABLE 
PARALLEL SAFE; 
