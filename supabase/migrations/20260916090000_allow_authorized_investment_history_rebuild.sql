-- Rebuilding FIFO history is an internal consequence of an already-authorized
-- Investment mutation. Only the incoming trade's selected wallet should need
-- wallet.use. Requiring wallet.use again for every historical trade makes a
-- valid new mutation fail when an older wallet grant was later removed.
--
-- investment_rebuild_asset is not executable by authenticated clients, so
-- removing these replay-time checks does not expose a new RPC surface.

do $migration$
declare
    function_definition text;
    funding_check text := $fragment$
            if not public.can_operate_wallet(wallet_row.id) then raise exception 'wallet.use is required for the funding wallet'; end if;
$fragment$;
    capital_return_check text := $fragment$
                if not public.can_operate_wallet(wallet_row.id) then raise exception 'wallet.use is required for the capital return wallet'; end if;
$fragment$;
begin
    select pg_get_functiondef(
        'public.investment_rebuild_asset(uuid,uuid,uuid,uuid,timestamp with time zone)'::regprocedure
    ) into function_definition;

    if strpos(function_definition, funding_check) = 0 then
        raise exception 'investment_rebuild_asset funding wallet permission fragment not found';
    end if;
    function_definition := replace(function_definition, funding_check, E'\n');

    if strpos(function_definition, capital_return_check) = 0 then
        raise exception 'investment_rebuild_asset capital-return wallet permission fragment not found';
    end if;
    function_definition := replace(function_definition, capital_return_check, E'\n');

    execute function_definition;
end;
$migration$;

revoke execute on function public.investment_rebuild_asset(uuid, uuid, uuid, uuid, timestamptz)
from public, anon, authenticated;

