--metadb:function count_circulation_history

DROP FUNCTION IF EXISTS count_circulation_history;
	
CREATE FUNCTION count_circulation_history(
	barcode_to_check text
)
returns table(
	circulation_history_count integer
)
as $$
select count(cit.id) AS circulation_history_count
  from folio_circulation.check_in__t__ as cit JOIN folio_inventory.item__t__ as itt ON cit.item_id = itt.id
  WHERE
    itt.__current = true and
    itt.barcode = barcode_to_check and
    cit.item_status_prior_to_check_in = 'Checked out'
$$
language sql
STABLE 
PARALLEL SAFE; 
