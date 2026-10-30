-- Buzz Masters — server-side verification for purchases, VIP and ad rewards.
--
-- Before this migration any signed-in client could call
-- monetisation_record_purchase / monetisation_grant_ad_reward with any
-- account id and simply claim a purchase or a verified advert. Now:
--
--   * those writers (and wallet_balance) run only as service_role, i.e. from
--     the Edge Functions in supabase/functions that verify RevenueCat
--     (webhook secret / REST API with the secret key) and AdMob (SSV ECDSA
--     signature) before writing anything;
--   * every remaining client RPC only acts on the caller's own account
--     (auth.uid()), via wrappers around the original bodies.
--
-- Also fixes monetisation_record_purchase, whose bundle loop referenced an
-- out-of-scope column `g` and failed on every bundle purchase.

-- ---------------------------------------------------------------------------
-- Fix: bundle grant loop
-- ---------------------------------------------------------------------------

create or replace function public.monetisation_record_purchase(
  p_account_id     text,
  p_transaction_id text,
  p_product_id     text,
  p_price_string   text,
  p_revoked        boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.monetisation_products%rowtype;
  v_duplicate boolean := false;
  v_grants text[] := '{}';
  v_item text;
begin
  if p_account_id is null or p_transaction_id is null or p_product_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Missing purchase fields.');
  end if;

  select * into v_product from public.monetisation_products where product_id = p_product_id;
  if not found then
    return jsonb_build_object('accepted', false, 'message', 'Unknown product.');
  end if;

  if exists (
    select 1 from public.purchase_events
    where account_id = p_account_id and transaction_id = p_transaction_id
  ) then
    v_duplicate := true;
  else
    insert into public.purchase_events (account_id, transaction_id, product_id, price_string, state, revoked)
    values (p_account_id, p_transaction_id, p_product_id, p_price_string,
            case when p_revoked then 'revoked' else 'success' end, coalesce(p_revoked, false));
  end if;

  if p_revoked then
    update public.player_entitlements
       set active = false, source = 'store', updated_at = now()
     where account_id = p_account_id and entitlement_key = coalesce(v_product.entitlement_key, '');
    update public.purchase_events set revoked = true, state = 'revoked'
     where account_id = p_account_id and transaction_id = p_transaction_id;
    insert into public.monetisation_audit_logs (account_id, action, detail)
    values (p_account_id, 'purchase_revoked',
            jsonb_build_object('transaction_id', p_transaction_id, 'product_id', p_product_id));
    return jsonb_build_object('accepted', true, 'duplicate', v_duplicate,
                              'granted_item_ids', '[]'::jsonb, 'message', 'Revoked.');
  end if;

  if v_product.entitlement_key is not null then
    insert into public.player_entitlements (account_id, entitlement_key, product_id, active, source, updated_at)
    values (p_account_id, v_product.entitlement_key, p_product_id, true, 'store', now())
    on conflict (account_id, entitlement_key) do update
      set product_id = excluded.product_id, active = true, source = 'store', updated_at = now();
  end if;

  for v_item in
    select jsonb_array_elements_text(
      case p_product_id
        when 'buzzmasters_starter_bundle' then '["frame_aurora","trail_neon","celebration_thunder"]'::jsonb
        when 'buzzmasters_neon_bundle'    then '["trail_neon","nameplate_chrome","frame_aurora"]'::jsonb
        when 'buzzmasters_legendary_bundle' then '["frame_aurora","trail_neon","celebration_thunder","nameplate_chrome","neon_phantom"]'::jsonb
        else '[]'::jsonb
      end)
  loop
    insert into public.player_inventory (account_id, item_id, category, granted_by)
    values (p_account_id, v_item,
            case
              when v_item like 'frame%' then 'profileFrames'
              when v_item like 'trail%' then 'racingTrails'
              when v_item like 'celebration%' then 'celebrations'
              when v_item like 'nameplate%' then 'nameplates'
              else 'avatars'
            end,
            p_transaction_id)
    on conflict (account_id, item_id) do nothing;
    v_grants := array_append(v_grants, v_item);
  end loop;

  insert into public.monetisation_audit_logs (account_id, action, detail)
  values (p_account_id, 'purchase_recorded',
          jsonb_build_object('transaction_id', p_transaction_id,
                             'product_id', p_product_id, 'duplicate', v_duplicate));

  return jsonb_build_object(
    'accepted', true,
    'duplicate', v_duplicate,
    'granted_item_ids', to_jsonb(v_grants),
    'message', case when v_duplicate then 'Already owned.' else '' end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Writers become server-only
-- ---------------------------------------------------------------------------

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end $$;

revoke execute on function
  public.monetisation_record_purchase(text, text, text, text, boolean),
  public.monetisation_grant_ad_reward(text, text, integer, boolean, integer, integer),
  public.wallet_balance(text)
from public, anon, authenticated;
grant execute on function
  public.monetisation_record_purchase(text, text, text, text, boolean),
  public.monetisation_grant_ad_reward(text, text, integer, boolean, integer, integer),
  public.wallet_balance(text)
to service_role;

-- ---------------------------------------------------------------------------
-- Client RPCs: own account only
-- ---------------------------------------------------------------------------

create or replace function public.monetisation_assert_own(p_account_id text)
returns void
language plpgsql stable
set search_path = public
as $$
begin
  if auth.uid() is null or p_account_id is distinct from auth.uid()::text then
    raise exception 'forbidden_account' using errcode = '42501';
  end if;
end $$;
revoke execute on function public.monetisation_assert_own(text) from public, anon, authenticated;

alter function public.monetisation_claim_daily_reward(text, integer)
  rename to monetisation_claim_daily_reward_unchecked;
alter function public.monetisation_equip(text, text, text)
  rename to monetisation_equip_unchecked;
alter function public.monetisation_join_tournament(text, uuid)
  rename to monetisation_join_tournament_unchecked;
alter function public.monetisation_entitlement(text)
  rename to monetisation_entitlement_unchecked;
revoke execute on function
  public.monetisation_claim_daily_reward_unchecked(text, integer),
  public.monetisation_equip_unchecked(text, text, text),
  public.monetisation_join_tournament_unchecked(text, uuid),
  public.monetisation_entitlement_unchecked(text)
from public, anon, authenticated;

create function public.monetisation_claim_daily_reward(p_account_id text, p_utc_day integer)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
begin
  perform monetisation_assert_own(p_account_id);
  return monetisation_claim_daily_reward_unchecked(p_account_id, p_utc_day);
end $$;

create function public.monetisation_equip(p_account_id text, p_category text, p_item_id text)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  perform monetisation_assert_own(p_account_id);
  perform monetisation_equip_unchecked(p_account_id, p_category, p_item_id);
end $$;

create function public.monetisation_join_tournament(p_account_id text, p_tournament_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
begin
  perform monetisation_assert_own(p_account_id);
  return monetisation_join_tournament_unchecked(p_account_id, p_tournament_id);
end $$;

create function public.monetisation_entitlement(p_account_id text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform monetisation_assert_own(p_account_id);
  return monetisation_entitlement_unchecked(p_account_id);
end $$;

revoke execute on function
  public.monetisation_claim_daily_reward(text, integer),
  public.monetisation_equip(text, text, text),
  public.monetisation_join_tournament(text, uuid),
  public.monetisation_entitlement(text)
from public, anon;
grant execute on function
  public.monetisation_claim_daily_reward(text, integer),
  public.monetisation_equip(text, text, text),
  public.monetisation_join_tournament(text, uuid),
  public.monetisation_entitlement(text)
to authenticated;

-- ---------------------------------------------------------------------------
-- Verified store events (RevenueCat webhook and REST sync)
-- ---------------------------------------------------------------------------

create table if not exists public.store_events (
  event_id        text primary key,
  account_id      text not null,
  product_id      text not null,
  transaction_id  text not null,
  revoked         boolean not null,
  expires_at      timestamptz,
  source          text not null check (source in ('revenuecat_webhook', 'revenuecat_sync')),
  received_at     timestamptz not null default now()
);
alter table public.store_events enable row level security;
revoke all on public.store_events from anon, authenticated;

-- Applies one verified store event exactly once.
create or replace function public.monetisation_store_event(
  p_event_id       text,
  p_account_id     text,
  p_transaction_id text,
  p_product_id     text,
  p_price_string   text,
  p_revoked        boolean,
  p_expires_at     timestamptz,
  p_will_renew     boolean,
  p_source         text
)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_result jsonb;
  v_key text;
begin
  if p_account_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return jsonb_build_object('accepted', false, 'message', 'Not a Buzz Masters account id.');
  end if;
  insert into store_events (event_id, account_id, product_id, transaction_id,
                            revoked, expires_at, source)
  values (p_event_id, p_account_id, p_product_id, p_transaction_id,
          p_revoked, p_expires_at, p_source)
  on conflict (event_id) do nothing;
  if not found then
    return jsonb_build_object('accepted', true, 'duplicate', true,
                              'granted_item_ids', '[]'::jsonb,
                              'message', 'Event already applied.');
  end if;

  v_result := monetisation_record_purchase(p_account_id, p_transaction_id,
                                           p_product_id, p_price_string,
                                           p_revoked);
  select entitlement_key into v_key
    from monetisation_products where product_id = p_product_id;
  if v_key is not null and not p_revoked then
    update player_entitlements
       set expires_at = p_expires_at,
           will_renew = coalesce(p_will_renew, false),
           updated_at = now()
     where account_id = p_account_id and entitlement_key = v_key;
  end if;
  return v_result;
end $$;

-- Auto-renew switched off: access continues until expiry.
create or replace function public.monetisation_store_renewal(
  p_event_id text, p_account_id text, p_product_id text, p_will_renew boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
begin
  insert into store_events (event_id, account_id, product_id, transaction_id,
                            revoked, source)
  values (p_event_id, p_account_id, p_product_id, 'renewal-change', false,
          'revenuecat_webhook')
  on conflict (event_id) do nothing;
  if not found then
    return jsonb_build_object('accepted', true, 'duplicate', true);
  end if;
  update player_entitlements e
     set will_renew = p_will_renew, updated_at = now()
    from monetisation_products p
   where p.product_id = p_product_id and e.entitlement_key = p.entitlement_key
     and e.account_id = p_account_id;
  return jsonb_build_object('accepted', true, 'duplicate', false);
end $$;

-- ---------------------------------------------------------------------------
-- Verified advert rewards (AdMob server-side verification)
-- ---------------------------------------------------------------------------

create or replace function public.monetisation_ssv_reward(
  p_account_id     text,
  p_event_id       text,
  p_utc_day        integer,
  p_coins          integer,
  p_max_per_day    integer
)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v jsonb;
begin
  v := monetisation_grant_ad_reward(p_account_id, p_event_id, p_utc_day, true,
                                    p_coins, p_max_per_day);
  update ad_reward_events set verification = 'ssv_verified'
   where account_id = p_account_id and event_id = p_event_id;
  return v;
end $$;

revoke execute on function
  public.monetisation_store_event(text, text, text, text, text, boolean, timestamptz, boolean, text),
  public.monetisation_store_renewal(text, text, text, boolean),
  public.monetisation_ssv_reward(text, text, integer, integer, integer)
from public, anon, authenticated;
grant execute on function
  public.monetisation_store_event(text, text, text, text, text, boolean, timestamptz, boolean, text),
  public.monetisation_store_renewal(text, text, text, boolean),
  public.monetisation_ssv_reward(text, text, integer, integer, integer)
to service_role;
