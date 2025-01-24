--metadb:function class_list

DROP FUNCTION IF EXISTS class_list;
	
CREATE FUNCTION class_list(
	note_string text
)
returns table(
	item_shelving_location test,
	call_number text,
	item_volume_number text,
	instance_author text,
	instance_title text,
	instance_publication_info text
)
as $$
select cit.id AS Check_In_ID, cit.occurred_date_time as Check_In_Date

FROM
	folio_notes.note__ as n
	LEFT JOIN SOMETHING ON n.id = 
    folio_inventory.instance__t
    LEFT JOIN folio_inventory.holdings__t ON instance__t.SOMETHING = holdings__t.SOMETHING
    LEFT JOIN folio_inventory.item__t ON holdings__t.SOMETHING = item__t.SOMETHING
	
	WHERE
	folio_notes.note__
    itt.__current = true and
    itt.barcode = barcode_to_check and
    cit.item_status_prior_to_check_in = 'Checked out' and
    start_date <= cit.occurred_date_time and cit.occurred_date_time <= end_date
$$
language sql
STABLE 
PARALLEL SAFE; 
