CREATE FUNCTION lrickards.count_internal_use(
    barcode bigint)
returns table(
	internal_use_count integer)
as $$
select count(cit.id)
	from folio_circulation.check_in__t__ cit JOIN folio_inventory.item__t__ itt ON cit.item_id = itt.id
	WHERE
		itt.__current = true and
		itt.barcode = barcode and
		item_status_prior_to_check_in = 'Available'
$$
language sql
STABLE 
PARALLEL SAFE; 
