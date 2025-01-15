--metadb:function zero_use_items

DROP FUNCTION IF EXISTS zero_use_items;
	
CREATE FUNCTION zero_use_items(
	start_date date DEFAULT '2000-01-01',
  end_date date DEFAULT '2099-01-01'
)
returns table(
	Check_In_ID text,
	Check_In_Date date
)
as $$
select cit.id AS Check_In_ID, cit.occurred_date_time as Check_In_Date
  from folio_circulation.check_in__t__ as cit JOIN folio_inventory.item__t__ as itt ON cit.item_id = itt.id
  WHERE
    itt.__current = true and
    cit.item_status_prior_to_check_in = 'Checked out' and
    start_date <= cit.occurred_date_time and cit.occurred_date_time <= end_date
$$
language sql
STABLE 
PARALLEL SAFE; 
