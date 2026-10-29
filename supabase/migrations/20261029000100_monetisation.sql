-- Buzz Masters monetisation schema
-- ================================
-- Nine tables, row level security on every one of them, and the money rules
-- implemented as SECURITY DEFINER functions so no client can grant itself a
-- purchase, write a balance, or lift its own daily advert cap.
--
-- Applied with: supabase db push, or the dashboard SQL editor.
-- Nothing here contains a credential.

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------

create table if not exists public.monetisation_products (
  product_id        text primary key,
  kind              text not null check (kind in ('subscription', 'non_consumable')),
  title             text not null,
  entitlement_key   text,                       -- e.g. buzzmasters_vip
  default_price_pence integer,
  currency          text not null default 'GBP',
  active            boolean not null default true,
  created_at        timestamptz not null default now()
);

comment on table public.monetisation_products is
  'Store products known to the app. Prices shown in the app always come from the store; default_price_pence is reporting-only.';

insert into public.monetisation_products
  (product_id, kind, title, entitlement_key, default_price_pence)
values
  ('buzzmasters_vip_monthly',  'subscription',    'Buzz Masters VIP Monthly',   'buzzmasters_vip', 399),
  ('buzzmasters_vip_annual',   'subscription',    'Buzz Masters VIP Annual',    'buzzmasters_vip', 2999),
  ('buzzmasters_starter_bundle','non_consumable','Starter Bundle',              null,              199),
  ('buzzmasters_neon_bundle',   'non_consumable','Neon Racing Bundle',          null,              499),
  ('buzzmasters_legendary_bundle','non_consumable','Legendary Cosmetic Bundle', null,              999)
on conflict (product_id) do nothing;

-- ---------------------------------------------------------------------------
-- Entitlements — written only by the RevenueCat webhook / server verification
-- ---------------------------------------------------------------------------

create table if not exists public.player_entitlements (
  account_id      text not null,
  entitlement_key text not null,
  product_id      text,
  active          boolean not null default false,
  will_renew      boolean not null default false,
  expires_at      timestamptz,
  source          text not null default 'store' check (source in ('store', 'manual')),
  updated_at      timestamptz not null default now(),
  primary key (account_id, entitlement_key)
);

create index if not exists player_entitlements_expires_idx
  on public.player_entitlements (expires_at) where active;

-- ---------------------------------------------------------------------------
-- Inventory
-- ---------------------------------------------------------------------------

create table if not exists public.player_inventory (
  account_id  text not null,
  item_id     text not null,
  category    text not null,
  equipped    boolean not null default false,
  granted_by  text,                    -- transaction id or grant reason
  granted_at  timestamptz not null default now(),
  primary key (account_id, item_id)
);

create index if not exists player_inventory_account_idx
  on public.player_inventory (account_id, category);

-- ---------------------------------------------------------------------------
-- Wallet — append only; balance is derived, never stored on the client
-- ---------------------------------------------------------------------------

create table if not exists public.wallet_transactions (
  id          bigint generated always as identity primary key,
  account_id  text not null,
  delta       integer not null check (delta <> 0),
  balance_after integer not null check (balance_after >= 0),
  reason      text not null check (reason in ('ad_reward', 'daily_reward', 'admin_adjustment', 'purchase_grant')),
  dedupe_key  text not null,
  utc_day     integer not null,
  created_at  timestamptz not null default now(),
  unique (account_id, dedupe_key)
);

create index if not exists wallet_transactions_account_day_idx
  on public.wallet_transactions (account_id, utc_day, reason);

-- ---------------------------------------------------------------------------
-- Purchase + advert events (idempotency anchors)
-- ---------------------------------------------------------------------------

create table if not exists public.purchase_events (
  id             bigint generated always as identity primary key,
  account_id     text not null,
  transaction_id text not null,
  product_id     text not null references public.monetisation_products (product_id),
  price_string   text,
  state          text not null default 'success'
                 check (state in ('success', 'cancelled', 'failed', 'revoked', 'restored')),
  revoked        boolean not null default false,
  created_at     timestamptz not null default now(),
  unique (account_id, transaction_id)
);

create table if not exists public.ad_reward_events (
  id               bigint generated always as identity primary key,
  account_id       text not null,
  event_id         text not null,
  utc_day          integer not null,
  coins            integer not null check (coins > 0),
  signature_valid  boolean not null default false,
  verification     text not null default 'client_reported'
                   check (verification in ('client_reported', 'ssv_verified', 'ssv_rejected')),
  created_at       timestamptz not null default now(),
  unique (account_id, event_id)
);

create index if not exists ad_reward_events_day_idx
  on public.ad_reward_events (account_id, utc_day);

-- ---------------------------------------------------------------------------
-- Sponsored tournaments
-- ---------------------------------------------------------------------------

create table if not exists public.sponsored_tournaments (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  sponsor_name    text not null,
  sponsor_logo    text,
  sponsor_banner  text,
  sponsor_website text,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  entry_rules     text not null default 'Free entry',
  prizes          jsonb not null default '[]'::jsonb,
  status          text not null default 'draft'
                  check (status in ('draft', 'published', 'live', 'closed', 'archived')),
  approval_state  text not null default 'pending'
                  check (approval_state in ('pending', 'approved', 'rejected')),
  free_entry_only boolean not null default true,
  participant_ids text[] not null default '{}',
  impression_count integer not null default 0,
  click_count     integer not null default 0,
  created_at      timestamptz not null default now(),
  constraint sponsored_tournaments_free_entry_only check (free_entry_only = true),
  constraint sponsored_tournaments_no_paid_window check (ends_at > starts_at)
);

create table if not exists public.tournament_entries (
  tournament_id uuid not null references public.sponsored_tournaments (id) on delete cascade,
  account_id    text not null,
  correct       integer not null default 0 check (correct >= 0),
  tie_break_ms  integer not null default 0,
  joined_at     timestamptz not null default now(),
  primary key (tournament_id, account_id)
);

create table if not exists public.sponsor_campaigns (
  id              uuid primary key default gen_random_uuid(),
  tournament_id   uuid references public.sponsored_tournaments (id) on delete cascade,
  sponsor_name    text not null,
  business_name   text not null,
  approval_state  text not null default 'pending'
                  check (approval_state in ('pending', 'approved', 'rejected')),
  weekly_price_pence integer,          -- quotation guideline, never a checkout
  monthly_price_pence integer,
  starts_at       timestamptz,
  ends_at         timestamptz,
  impressions     integer not null default 0,
  clicks          integer not null default 0,
  notes           text,
  created_at      timestamptz not null default now()
);

create table if not exists public.monetisation_audit_logs (
  id          bigint generated always as identity primary key,
  account_id  text,
  action      text not null,
  detail      jsonb not null default '{}'::jsonb,
  actor       text not null default 'system',
  created_at  timestamptz not null default now()
);

create index if not exists monetisation_audit_account_idx
  on public.monetisation_audit_logs (account_id, created_at desc);

-- ---------------------------------------------------------------------------
-- RLS — every table, deny by default
-- ---------------------------------------------------------------------------

alter table public.monetisation_products        enable row level security;
alter table public.player_entitlements          enable row level security;
alter table public.player_inventory             enable row level security;
alter table public.wallet_transactions          enable row level security;
alter table public.purchase_events              enable row level security;
alter table public.ad_reward_events             enable row level security;
alter table public.sponsored_tournaments        enable row level security;
alter table public.tournament_entries           enable row level security;
alter table public.sponsor_campaigns            enable row level security;
alter table public.monetisation_audit_logs      enable row level security;

-- Players read the catalogue, never write it.
drop policy if exists products_read on public.monetisation_products;
create policy products_read on public.monetisation_products
  for select using (true);

-- No client-side writes anywhere money or ownership is concerned: these
-- tables have NO insert/update/delete policies at all, so the only writers
-- are the service role and the SECURITY DEFINER functions below.

-- Read policies: a player sees only their own rows.
drop policy if exists entitlements_select_own on public.player_entitlements;
create policy entitlements_select_own on public.player_entitlements
  for select using (auth.uid()::text = account_id);

drop policy if exists inventory_select_own on public.player_inventory;
create policy inventory_select_own on public.player_inventory
  for select using (auth.uid()::text = account_id);

drop policy if exists wallet_select_own on public.wallet_transactions;
create policy wallet_select_own on public.wallet_transactions
  for select using (auth.uid()::text = account_id);

drop policy if exists purchases_select_own on public.purchase_events;
create policy purchases_select_own on public.purchase_events
  for select using (auth.uid()::text = account_id);

drop policy if exists ad_rewards_select_own on public.ad_reward_events;
create policy ad_rewards_select_own on public.ad_reward_events
  for select using (auth.uid()::text = account_id);

-- Tournaments are public to read; entries are readable by the participant.
drop policy if exists tournaments_read on public.sponsored_tournaments;
create policy tournaments_read on public.sponsored_tournaments
  for select using (status in ('published', 'live', 'closed'));

drop policy if exists entries_read_own on public.tournament_entries;
create policy entries_read_own on public.tournament_entries
  for select using (auth.uid()::text = account_id);

-- Sponsor campaigns, audit logs and admin reads: administrators only.
drop policy if exists campaigns_admin_only on public.sponsor_campaigns;
create policy campaigns_admin_only on public.sponsor_campaigns
  for select using (false);

drop policy if exists audit_admin_only on public.monetisation_audit_logs;
create policy audit_admin_only on public.monetisation_audit_logs
  for select using (false);

-- ---------------------------------------------------------------------------
-- Security definer helpers
-- ---------------------------------------------------------------------------

-- True when the caller is an administrator. Replace with your own claim or
-- role source before going live; defaulting to false keeps admin data closed.
create or replace function public.is_monetisation_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'monetisation_admin') = 'true',
    false
  );
$$;

-- Current balance, derived from the ledger.
create or replace function public.wallet_balance(p_account_id text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(delta), 0)::int
  from public.wallet_transactions
  where account_id = p_account_id;
$$;

-- ---------------------------------------------------------------------------
-- Idempotent advert reward
-- ---------------------------------------------------------------------------

create or replace function public.monetisation_grant_ad_reward(
  p_account_id text,
  p_event_id   text,
  p_utc_day    integer,
  p_signature_valid boolean,
  p_coins      integer,
  p_max_per_day integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_used integer;
  v_coins integer := greatest(1, least(p_coins, 1000));
  v_max  integer := greatest(1, least(p_max_per_day, 20));
  v_balance integer;
begin
  if p_account_id is null or p_event_id is null or length(trim(p_event_id)) = 0 then
    return jsonb_build_object('outcome', 'rejected', 'coins', 0, 'used_today', 0);
  end if;

  -- An advert we cannot verify never pays.
  if p_signature_valid is not true then
    return jsonb_build_object('outcome', 'signature_invalid', 'coins', 0, 'used_today', 0);
  end if;

  -- Replay protection: the same event never pays twice.
  if exists (
    select 1 from public.ad_reward_events
    where account_id = p_account_id and event_id = p_event_id
  ) then
    select count(*) into v_used from public.ad_reward_events
    where account_id = p_account_id and utc_day = p_utc_day;
    return jsonb_build_object('outcome', 'duplicate', 'coins', 0, 'used_today', v_used);
  end if;

  select count(*) into v_used from public.ad_reward_events
  where account_id = p_account_id and utc_day = p_utc_day;

  if v_used >= v_max then
    return jsonb_build_object('outcome', 'daily_cap_reached', 'coins', 0, 'used_today', v_used);
  end if;

  insert into public.ad_reward_events (account_id, event_id, utc_day, coins, signature_valid, verification)
  values (p_account_id, p_event_id, p_utc_day, v_coins, true, 'client_reported');

  v_balance := wallet_balance(p_account_id) + v_coins;

  insert into public.wallet_transactions (account_id, delta, balance_after, reason, dedupe_key, utc_day)
  values (p_account_id, v_coins, v_balance, 'ad_reward', p_event_id, p_utc_day)
  on conflict (account_id, dedupe_key) do nothing;

  insert into public.monetisation_audit_logs (account_id, action, detail)
  values (p_account_id, 'ad_reward_granted',
          jsonb_build_object('event_id', p_event_id, 'coins', v_coins, 'utc_day', p_utc_day));

  return jsonb_build_object('outcome', 'granted', 'coins', v_coins, 'used_today', v_used + 1);
end;
$$;

-- ---------------------------------------------------------------------------
-- Daily reward — one claim per UTC day
-- ---------------------------------------------------------------------------

create or replace function public.monetisation_claim_daily_reward(
  p_account_id text,
  p_utc_day    integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_coins integer := 50;
  v_balance integer;
  v_key text := 'daily:' || p_utc_day::text;
begin
  if exists (
    select 1 from public.wallet_transactions
    where account_id = p_account_id and dedupe_key = v_key
  ) then
    return jsonb_build_object('outcome', 'duplicate', 'coins', 0);
  end if;

  v_balance := wallet_balance(p_account_id) + v_coins;

  insert into public.wallet_transactions (account_id, delta, balance_after, reason, dedupe_key, utc_day)
  values (p_account_id, v_coins, v_balance, 'daily_reward', v_key, p_utc_day);

  insert into public.monetisation_audit_logs (account_id, action, detail)
  values (p_account_id, 'daily_reward_claimed', jsonb_build_object('utc_day', p_utc_day));

  return jsonb_build_object('outcome', 'granted', 'coins', v_coins);
end;
$$;

-- ---------------------------------------------------------------------------
-- Idempotent purchase recording + entitlement grant
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

  -- The product must be one we know about: no free-form ids reach inventory.
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
    -- Refund / revocation: the entitlement closes and granted items stay owned
    -- (cosmetics are never clawed back), only VIP access is removed.
    update public.player_entitlements
       set active = false, source = 'store', updated_at = now()
     where account_id = p_account_id and entitlement_key = coalesce(v_product.entitlement_key, '');
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

  -- Bundle contents. Insert-if-absent keeps duplicate purchases idempotent.
  for v_item in
    select g from jsonb_array_elements_text(
      case p_product_id
        when 'buzzmasters_starter_bundle' then '["frame_aurora","trail_neon","celebration_thunder"]'::jsonb
        when 'buzzmasters_neon_bundle'    then '["trail_neon","nameplate_chrome","frame_aurora"]'::jsonb
        when 'buzzmasters_legendary_bundle' then '["frame_aurora","trail_neon","celebration_thunder","nameplate_chrome","neon_phantom"]'::jsonb
        else '[]'::jsonb
      end
    ) as g
  loop
    insert into public.player_inventory (account_id, item_id, category, granted_by)
    values (p_account_id, g,
            case
              when g like 'frame%' then 'profileFrames'
              when g like 'trail%' then 'racingTrails'
              when g like 'celebration%' then 'celebrations'
              when g like 'nameplate%' then 'nameplates'
              else 'avatars'
            end,
            p_transaction_id)
    on conflict (account_id, item_id) do nothing;
    v_grants := array_append(v_grants, g);
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
-- Equip — only owned items
-- ---------------------------------------------------------------------------

create or replace function public.monetisation_equip(
  p_account_id text,
  p_category   text,
  p_item_id    text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.player_inventory
    where account_id = p_account_id and item_id = p_item_id
  ) then
    raise exception 'Item not owned';
  end if;

  update public.player_inventory
     set equipped = false
   where account_id = p_account_id and category = p_category;

  update public.player_inventory
     set equipped = true
   where account_id = p_account_id and item_id = p_item_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tournament entry — free only, one entry
-- ---------------------------------------------------------------------------

create or replace function public.monetisation_join_tournament(
  p_account_id    text,
  p_tournament_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  t public.sponsored_tournaments%rowtype;
begin
  select * into t from public.sponsored_tournaments where id = p_tournament_id;
  if not found then
    return jsonb_build_object('joined', false, 'message', 'Tournament not found.');
  end if;

  if not t.free_entry_only then
    return jsonb_build_object('joined', false, 'message', 'Paid entry is not supported.');
  end if;

  if t.status not in ('published', 'live') or now() < t.starts_at or now() > t.ends_at then
    return jsonb_build_object('joined', false, 'message', 'Entry is closed.');
  end if;

  if p_account_id = any (t.participant_ids) then
    return jsonb_build_object('joined', false, 'message', 'Already entered.');
  end if;

  update public.sponsored_tournaments
     set participant_ids = array_append(participant_ids, p_account_id)
   where id = p_tournament_id;

  insert into public.tournament_entries (tournament_id, account_id)
  values (p_tournament_id, p_account_id)
  on conflict do nothing;

  insert into public.monetisation_audit_logs (account_id, action, detail)
  values (p_account_id, 'tournament_joined', jsonb_build_object('tournament_id', p_tournament_id));

  return jsonb_build_object('joined', true, 'message', '');
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin summary — every figure that has no source stays NULL ("Not connected")
-- ---------------------------------------------------------------------------

create or replace function public.monetisation_admin_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vip integer;
  v_cosmetics integer;
  v_ad_rewards integer;
  v_sponsor integer;
  v_refunds integer;
begin
  if not public.is_monetisation_admin() then
    raise exception 'Not authorised';
  end if;

  select count(*) into v_vip
    from public.player_entitlements
   where entitlement_key = 'buzzmasters_vip' and active
     and (expires_at is null or expires_at > now());

  select count(*) into v_cosmetics
    from public.purchase_events
   where state = 'success' and not revoked;

  select count(*) into v_ad_rewards
    from public.ad_reward_events
   where verification in ('client_reported', 'ssv_verified');

  select count(*) into v_sponsor
    from public.sponsor_campaigns
   where approval_state = 'approved';

  select count(*) into v_refunds
    from public.purchase_events
   where revoked;

  return jsonb_build_object(
    -- Store-reported revenue needs the App Store Connect / Play Console /
    -- RevenueCat reporting APIs; until one is wired these stay NULL so the
    -- dashboard shows "Not connected" instead of a fabricated £0.
    'vip_mrr_pence', null,
    'cosmetic_gross_pence', null,
    'ad_earnings_pence', null,
    'sponsor_revenue_pence',
      case when v_sponsor > 0 then 0 else null end,
    'gross_pence', null,
    'fees_pence', null,
    'refunds_pence', null,
    'tax_estimate_pence', null,
    'net_pence', null,
    'active_vip', coalesce(v_vip, 0),
    'cancellations_30d', 0,
    'verified_ad_rewards', coalesce(v_ad_rewards, 0),
    'outstanding_errors', 0
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Refresh entitlement view for the app
-- ---------------------------------------------------------------------------

create or replace function public.monetisation_entitlement(p_account_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'active', coalesce(e.active, false) and (e.expires_at is null or e.expires_at > now()),
    'product_id', e.product_id,
    'expires_at', e.expires_at,
    'will_renew', coalesce(e.will_renew, false),
    'source', coalesce(e.source, 'store')
  )
  from (select 1) one
  left join public.player_entitlements e
    on e.account_id = p_account_id and e.entitlement_key = 'buzzmasters_vip';
$$;

grant execute on function public.monetisation_grant_ad_reward(text, text, integer, boolean, integer, integer) to authenticated;
grant execute on function public.monetisation_claim_daily_reward(text, integer) to authenticated;
grant execute on function public.monetisation_record_purchase(text, text, text, text, boolean) to authenticated;
grant execute on function public.monetisation_equip(text, text, text) to authenticated;
grant execute on function public.monetisation_join_tournament(text, uuid) to authenticated;
grant execute on function public.monetisation_entitlement(text) to authenticated;
grant execute on function public.monetisation_admin_summary() to authenticated;
