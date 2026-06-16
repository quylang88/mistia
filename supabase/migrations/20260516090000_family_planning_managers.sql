alter table public.families
    add column if not exists budget_manager_user_id uuid references auth.users(id) on delete set null,
    add column if not exists goal_manager_user_id uuid references auth.users(id) on delete set null;

create index if not exists families_budget_manager_user_id_idx
    on public.families(budget_manager_user_id)
    where budget_manager_user_id is not null;

create index if not exists families_goal_manager_user_id_idx
    on public.families(goal_manager_user_id)
    where goal_manager_user_id is not null;

create or replace function public.set_family_planning_manager(
    p_family_id uuid,
    p_resource_type text,
    p_manager_user_id uuid
)
returns public.families
language plpgsql
security definer
set search_path = public
as $$
declare
    actor_id uuid := auth.uid();
    family_row public.families;
begin
    if actor_id is null then
        raise exception 'Not authenticated';
    end if;

    if p_resource_type not in ('budget', 'goal') then
        raise exception 'Unsupported planning manager resource type';
    end if;

    if not public.is_family_owner(p_family_id) then
        raise exception 'Only the family owner can change planning managers';
    end if;

    if p_manager_user_id is not null
       and not public.active_family_member_exists(p_family_id, p_manager_user_id) then
        raise exception 'Planning manager must be an active family member';
    end if;

    if p_resource_type = 'budget' then
        update public.families
        set budget_manager_user_id = p_manager_user_id,
            updated_at = timezone('utc'::text, now())
        where id = p_family_id
          and deleted_at is null
        returning * into family_row;
    else
        update public.families
        set goal_manager_user_id = p_manager_user_id,
            updated_at = timezone('utc'::text, now())
        where id = p_family_id
          and deleted_at is null
        returning * into family_row;
    end if;

    if family_row.id is null then
        raise exception 'Family not found';
    end if;

    return family_row;
end;
$$;

grant execute on function public.set_family_planning_manager(uuid, text, uuid) to authenticated;
