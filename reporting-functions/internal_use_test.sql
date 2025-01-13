--metadb:function internal_use_test

DROP FUNCTION IF EXISTS internal_use_test;
	
CREATE FUNCTION internal_use_test(barcode bigint)
returns table()
as $$
select * from folio_circulation.check_in__t__ as cit JOIN folio_inventory.item__t__ as itt ON cit.item_id = itt.id
  WHERE
    itt.__current = true and
    itt.barcode = barcode and
    cit.item_status_prior_to_check_in = 'Available'
$$
language sql
STABLE 
PARALLEL SAFE; 
