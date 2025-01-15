--metadb:function count_circulation_history

DROP FUNCTION IF EXISTS count_circulation_history;
	
CREATE FUNCTION count_circulation_history(
	barcode_to_check text,
	start_date date DEFAULT '2000-01-01',
  	end_date date DEFAULT '2099-01-01'
)
returns table(
	circulation_history_count integer,
	date_to_display date
)
as $$
select cit.id AS circulation_history_count, cit.occurred_date_time
  from folio_circulation.check_in__t__ as cit JOIN folio_inventory.item__t__ as itt ON cit.item_id = itt.id
  WHERE
    itt.__current = true and
    itt.barcode = barcode_to_check and
    cit.item_status_prior_to_check_in = 'Checked out' and
    start_date <= cit.occurred_date_time and cit.occurred_date_time <= end_date
$$
language sql
STABLE 
PARALLEL SAFE; 
