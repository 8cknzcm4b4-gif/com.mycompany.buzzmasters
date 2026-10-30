-- Buzz Masters — account deletion (App Store guideline 5.1.1(v)).
--
-- bm_purge_account() erases everything tied to a player. It runs only as
-- service_role, from the delete-account Edge Function, which first verifies
-- the caller's own JWT and afterwards deletes the auth user itself.
--
-- Race data hangs off player_profiles and is removed by ON DELETE CASCADE
-- (rooms they host, seats, answers, results, friends, invites). Monetisation
-- rows are keyed by text account ids, so they are deleted explicitly. Store
-- receipts remain with Apple/Google/RevenueCat, outside this database.

create or replace function public.bm_purge_account(p_user uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id text := p_user::text;
  v_counts jsonb;
begin
  if p_user is null then
    return jsonb_build_object('ok', false, 'error', 'no_user');
  end if;

  -- Rooms this player is in but does not host: free the seat for others.
  delete from race_room_players p
    using race_rooms r
   where p.room_id = r.id and p.player_id = p_user and r.host_id <> p_user
     and r.status = 'lobby';

  with
    w as (delete from wallet_transactions where account_id = v_id returning 1),
    e as (delete from player_entitlements where account_id = v_id returning 1),
    i as (delete from player_inventory where account_id = v_id returning 1),
    p as (delete from purchase_events where account_id = v_id returning 1),
    a as (delete from ad_reward_events where account_id = v_id returning 1),
    t as (delete from tournament_entries where account_id = v_id returning 1),
    s as (delete from store_events where account_id = v_id returning 1),
    l as (delete from monetisation_audit_logs where account_id = v_id returning 1),
    pr as (delete from player_profiles where id = p_user returning 1)
  select jsonb_build_object(
    'wallet', (select count(*) from w),
    'entitlements', (select count(*) from e),
    'inventory', (select count(*) from i),
    'purchases', (select count(*) from p),
    'ad_rewards', (select count(*) from a),
    'tournament_entries', (select count(*) from t),
    'store_events', (select count(*) from s),
    'audit_logs', (select count(*) from l),
    'profile', (select count(*) from pr))
  into v_counts;

  return jsonb_build_object('ok', true, 'deleted', v_counts);
end $$;

revoke execute on function public.bm_purge_account(uuid) from public, anon, authenticated;
grant execute on function public.bm_purge_account(uuid) to service_role;
