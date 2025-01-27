--metadb:function class_list

DROP FUNCTION IF EXISTS class_list;
	
CREATE FUNCTION class_list(
	note_string text
)
returns table(
	item_barcode text,
	location_code text,
	location_name text,
	item_call_number text,
	instance_title text,
	item_note text
)
as $$
	
select distinct 
	i.jsonb ->> 'barcode' as item_barcode, 
	lt.code as location_code,
	lt.name as location_name,
	concat_ws(' ', i.jsonb -> 'effectiveCallNumberComponents'->>'prefix', i.jsonb -> 'effectiveCallNumberComponents'->>'callNumber', i.jsonb ->> 'copyNumber') as item_callnumber,
	inst.title as instance_title,
	jsonb_extract_path_text(notes.data, 'note') as item_note
from folio_inventory.item__ as i
cross join lateral jsonb_array_elements(jsonb_extract_path(i.jsonb, 'notes')) with ordinality as notes (data)
left join folio_inventory.item__t__ as it on i.id = it.id
left join folio_inventory.holdings_record__t__ as hrt on it.holdings_record_id = hrt.id
left join folio_inventory.instance__t__ as inst on hrt.instance_id = inst.id
left join folio_inventory.location__t__ as lt on hrt.effective_location_id = lt.id
--left join folio_derived.instance_contributors as ic on inst.id = ic.instance_id    /* might add this line to include the author */

where jsonb_extract_path_text(notes.data, 'note') like ('%' || note_string || '%')

$$
language sql
STABLE 
PARALLEL SAFE; 
