--metadb:function count_internal_use

DROP FUNCTION IF EXISTS count_internal_use;
	
CREATE FUNCTION count_internal_use(
	barcode text
)
returns table(
	internal_use_count integer
)
as $$
select count(cit.id) AS internal_use_count
  from folio_circulation.check_in__t__ as cit JOIN folio_inventory.item__t__ as itt ON cit.item_id = itt.id
  WHERE
    itt.__current = true and
    itt.barcode = barcode and
    cit.item_status_prior_to_check_in = 'Available'
$$
language sql
STABLE 
PARALLEL SAFE; 
