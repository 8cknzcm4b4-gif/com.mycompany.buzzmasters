-- Buzz Masters — community, moderation, readiness, public lobbies, question
-- rotation, period rankings, notifications, rate limits and Realtime signals.
--
-- Builds on 20261030000100_multiplayer.sql. Same rules: clients cannot touch
-- tables except the two Realtime tables below, which they may only SELECT,
-- and only their own rows (RLS). Everything else goes through bm_* RPCs.
-- New rows hang off player_profiles with ON DELETE CASCADE, so
-- bm_purge_account() (account deletion) removes them too.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

alter table public.race_room_players
  add column if not exists ready boolean not null default false;
alter table public.race_rooms
  add column if not exists is_public boolean not null default false;
alter table public.race_questions
  add column if not exists needs_review boolean not null default false;

create index if not exists race_rooms_public_lobby_idx
  on public.race_rooms (created_at)
  where status = 'lobby' and is_public;
create index if not exists race_results_recorded_idx
  on public.race_results (recorded_at);

create table if not exists public.player_blocks (
  blocker uuid not null references public.player_profiles (id) on delete cascade,
  blocked uuid not null references public.player_profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
create index if not exists player_blocks_blocked_idx
  on public.player_blocks (blocked);

create table if not exists public.player_reports (
  id bigint generated always as identity primary key,
  reporter uuid not null references public.player_profiles (id) on delete cascade,
  target uuid not null references public.player_profiles (id) on delete cascade,
  room_id uuid references public.race_rooms (id) on delete set null,
  reason text not null
    check (reason in ('offensive_name', 'cheating', 'harassment', 'other')),
  details text check (char_length(details) <= 280),
  status text not null default 'open'
    check (status in ('open', 'actioned', 'dismissed')),
  created_at timestamptz not null default now(),
  check (reporter <> target)
);
create index if not exists player_reports_target_idx
  on public.player_reports (target, status);
create index if not exists player_reports_reporter_idx
  on public.player_reports (reporter);

create table if not exists public.question_reports (
  id bigint generated always as identity primary key,
  reporter uuid not null references public.player_profiles (id) on delete cascade,
  question_id text not null references public.race_questions (id) on delete cascade,
  room_id uuid references public.race_rooms (id) on delete set null,
  reason text not null
    check (reason in ('wrong_answer', 'unclear', 'offensive', 'other')),
  details text check (char_length(details) <= 280),
  created_at timestamptz not null default now(),
  unique (reporter, question_id)
);
create index if not exists question_reports_question_idx
  on public.question_reports (question_id);

-- Which questions each player has seen recently, so races avoid repeats.
create table if not exists public.player_question_history (
  player_id uuid not null references public.player_profiles (id) on delete cascade,
  question_id text not null references public.race_questions (id) on delete cascade,
  seen_at timestamptz not null,
  primary key (player_id, question_id)
);

create table if not exists public.player_notifications (
  id bigint generated always as identity primary key,
  player_id uuid not null references public.player_profiles (id) on delete cascade,
  kind text not null
    check (kind in ('friend_request', 'friend_accepted', 'race_invite',
                    'race_result')),
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists player_notifications_player_idx
  on public.player_notifications (player_id, id desc);

-- One row per room; `version` changes whenever the room or a seat changes.
-- Members subscribe to it over Realtime and refetch the (server-built) state.
-- No foreign key: it may outlive a room for a moment during deletes, and a
-- row nobody can see is harmless.
create table if not exists public.race_room_signals (
  room_id uuid primary key,
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);

-- Fixed-window counters for abuse protection.
create table if not exists public.bm_rate_hits (
  player_id uuid not null references public.player_profiles (id) on delete cascade,
  action text not null,
  bucket timestamptz not null,
  hits int not null default 0,
  primary key (player_id, action, bucket)
);

alter table public.player_blocks enable row level security;
alter table public.player_reports enable row level security;
alter table public.question_reports enable row level security;
alter table public.player_question_history enable row level security;
alter table public.player_notifications enable row level security;
alter table public.race_room_signals enable row level security;
alter table public.bm_rate_hits enable row level security;
revoke all on public.player_blocks, public.player_reports,
  public.question_reports, public.player_question_history,
  public.player_notifications, public.race_room_signals, public.bm_rate_hits
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

create or replace function public.bm_is_blocked(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from player_blocks
                 where (blocker = a and blocked = b)
                    or (blocker = b and blocked = a))
$$;

-- True when the call is within the limit, counting this call.
create or replace function public.bm_rate_ok(
  p_player uuid, p_action text, p_max int, p_window_seconds int)
returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare
  v_bucket timestamptz := to_timestamp(
    floor(extract(epoch from race_now()) / p_window_seconds) * p_window_seconds);
  v_hits int;
begin
  insert into bm_rate_hits (player_id, action, bucket, hits)
  values (p_player, p_action, v_bucket, 1)
  on conflict (player_id, action, bucket)
    do update set hits = bm_rate_hits.hits + 1
  returning hits into v_hits;
  delete from bm_rate_hits
    where player_id = p_player and action = p_action
      and bucket < v_bucket - make_interval(secs => p_window_seconds);
  return v_hits <= p_max;
end $$;

create or replace function public.bm_notify(
  p_player uuid, p_kind text, p_payload jsonb) returns void
language sql volatile security definer set search_path = public as $$
  insert into player_notifications (player_id, kind, payload)
  values (p_player, p_kind, p_payload)
$$;

-- Used by the Realtime RLS policy below.
create or replace function public.bm_is_room_member(p_room uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from race_room_players
                 where room_id = p_room and player_id = auth.uid())
$$;

-- ---------------------------------------------------------------------------
-- Realtime: room signals and notifications
-- ---------------------------------------------------------------------------

create or replace function public.race_signal(p_room uuid) returns void
language sql volatile security definer set search_path = public as $$
  insert into race_room_signals (room_id, version, updated_at)
  select p_room, 1, now() where exists (select 1 from race_rooms where id = p_room)
  on conflict (room_id) do update
    set version = race_room_signals.version + 1, updated_at = now()
$$;

create or replace function public.race_rooms_signal() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and to_jsonb(new) = to_jsonb(old) then
    return null;
  end if;
  if tg_op = 'DELETE' then
    delete from race_room_signals where room_id = old.id;
  else
    perform race_signal(new.id);
  end if;
  return null;
end $$;

create or replace function public.race_seats_signal() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Polls only refresh last_seen; signalling those would make every client
  -- refetch, refresh last_seen again, and loop.
  if tg_op = 'UPDATE'
     and to_jsonb(new) - 'last_seen' = to_jsonb(old) - 'last_seen' then
    return null;
  end if;
  if tg_op = 'DELETE' then
    perform race_signal(old.room_id);
  else
    perform race_signal(new.room_id);
  end if;
  return null;
end $$;

drop trigger if exists race_rooms_signal on public.race_rooms;
create trigger race_rooms_signal
  after insert or update or delete on public.race_rooms
  for each row execute function public.race_rooms_signal();
drop trigger if exists race_room_players_signal on public.race_room_players;
create trigger race_room_players_signal
  after insert or update or delete on public.race_room_players
  for each row execute function public.race_seats_signal();

drop policy if exists "members see their room signal" on public.race_room_signals;
create policy "members see their room signal" on public.race_room_signals
  for select to authenticated using (public.bm_is_room_member(room_id));
drop policy if exists "players see their notifications" on public.player_notifications;
create policy "players see their notifications" on public.player_notifications
  for select to authenticated using (player_id = auth.uid());
grant select on public.race_room_signals, public.player_notifications
  to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime'
                     and tablename = 'race_room_signals') then
      alter publication supabase_realtime add table public.race_room_signals;
    end if;
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime'
                     and tablename = 'player_notifications') then
      alter publication supabase_realtime add table public.player_notifications;
    end if;
  end if;
end $$;

-- Notifications written by the server as things happen.
create or replace function public.race_notify_friend() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    perform bm_notify(new.addressee, 'friend_request', jsonb_build_object(
      'from_id', new.requester,
      'from', (select display_name from player_profiles where id = new.requester)));
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'accepted' then
    perform bm_notify(new.requester, 'friend_accepted', jsonb_build_object(
      'from_id', new.addressee,
      'from', (select display_name from player_profiles where id = new.addressee)));
  end if;
  return null;
end $$;
drop trigger if exists friend_links_notify on public.friend_links;
create trigger friend_links_notify
  after insert or update on public.friend_links
  for each row execute function public.race_notify_friend();

create or replace function public.race_notify_invite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform bm_notify(new.to_id, 'race_invite', jsonb_build_object(
    'room_id', new.room_id,
    'code', (select code from race_rooms where id = new.room_id),
    'from_id', new.from_id,
    'from', (select display_name from player_profiles where id = new.from_id)));
  return null;
end $$;
drop trigger if exists race_invites_notify on public.race_invites;
create trigger race_invites_notify
  after insert or update on public.race_invites
  for each row execute function public.race_notify_invite();

create or replace function public.race_notify_result() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform bm_notify(new.player_id, 'race_result', jsonb_build_object(
    'room_id', new.room_id, 'placing', new.finish_place));
  return null;
end $$;
drop trigger if exists race_results_notify on public.race_results;
create trigger race_results_notify
  after insert on public.race_results
  for each row execute function public.race_notify_result();

-- ---------------------------------------------------------------------------
-- Room state: now includes readiness and whether the lobby is public.
-- ---------------------------------------------------------------------------

create or replace function public.race_state_json(p_room uuid, p_me uuid)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  r race_rooms;
  t timestamptz := race_now();
  q race_questions;
  v_players jsonb;
  v_question jsonb := null;
  v_mine jsonb := null;
  v_results jsonb := null;
begin
  select * into r from race_rooms where id = p_room;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.player_id,
           'seat', p.seat,
           'name', pr.display_name,
           'color', pr.color_index,
           'progress', p.progress,
           'speed', p.speed,
           'finished', p.finished_ms is not null,
           'finished_ms', p.finished_ms,
           'eliminated', p.eliminated,
           'danger', p.finished_ms is null and not p.eliminated
                     and r.questions_resolved >= race_rule('danger_free')
                     and p.progress <= race_rule('danger_max'),
           'connected', p.left_at is null
                        and p.last_seen > t - make_interval(secs => race_rule('stale_seconds')),
           'left', p.left_at is not null,
           'ready', p.ready or p.player_id = r.host_id,
           'is_me', p.player_id = p_me,
           'is_host', p.player_id = r.host_id
         ) order by p.seat), '[]'::jsonb)
    into v_players
    from race_room_players p
    join player_profiles pr on pr.id = p.player_id
    where p.room_id = p_room;

  if r.status = 'racing' and r.current_q >= 0 then
    select * into q from race_questions where id = r.question_ids[r.current_q + 1];
    if t >= r.q_opened_at then
      v_question := jsonb_build_object(
        'index', r.current_q,
        'category', q.category,
        'difficulty', q.difficulty,
        'prompt', q.prompt,
        'options', to_jsonb(q.options),
        'remaining_ms', greatest(0, race_rule('window_ms')
          - (extract(epoch from (t - r.q_opened_at)) * 1000)::int));
    end if;
    select jsonb_build_object('option', a.option_index, 'correct', a.correct,
                              'delta', a.delta)
      into v_mine
      from race_answers a
      where a.room_id = p_room and a.player_id = p_me and a.q_index = r.current_q;
  end if;

  if r.status = 'finished' then
    select jsonb_agg(jsonb_build_object(
             'id', rr.player_id, 'placing', rr.finish_place, 'name', pr.display_name,
             'color', pr.color_index, 'progress', rr.progress,
             'finished', rr.finished, 'eliminated', rr.eliminated,
             'correct', rr.correct, 'answered', rr.answered,
             'is_me', rr.player_id = p_me) order by rr.finish_place)
      into v_results
      from race_results rr join player_profiles pr on pr.id = rr.player_id
      where rr.room_id = p_room;
  end if;

  return jsonb_build_object(
    'ok', true,
    'room_id', r.id,
    'code', r.code,
    'status', r.status,
    'is_public', r.is_public,
    'host_id', r.host_id,
    'is_host', r.host_id = p_me,
    'all_ready', not exists (select 1 from race_room_players p
                             where p.room_id = p_room and p.left_at is null
                               and not p.ready and p.player_id <> r.host_id),
    'countdown_ms', case when r.status = 'countdown'
      then greatest(0, (extract(epoch from (r.starts_at - t)) * 1000)::int) end,
    'question_number', r.current_q + 1,
    'questions_resolved', r.questions_resolved,
    'next_question_in_ms', case when r.status = 'racing' and t < r.q_opened_at
      then (extract(epoch from (r.q_opened_at - t)) * 1000)::int end,
    'last_correct_index', r.last_correct_index,
    'rules', jsonb_build_object(
      'distance', race_rule('distance'),
      'window_ms', race_rule('window_ms'),
      'max_questions', race_rule('max_questions'),
      'max_seats', race_rule('max_seats'),
      'min_players', race_rule('min_players')),
    'players', v_players,
    'question', v_question,
    'my_answer', v_mine,
    'results', v_results);
end $$;

-- ---------------------------------------------------------------------------
-- Lobbies: public or private, rate limited, readiness
-- ---------------------------------------------------------------------------

create or replace function public.bm_create_room(p_public boolean) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  v_code text;
  v_room uuid;
  t timestamptz := race_now();
begin
  if not bm_rate_ok(v_me, 'create_room', 20, 3600) then
    return race_err('rate_limited');
  end if;
  loop
    v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from race_rooms where code = v_code
                          and status in ('lobby', 'countdown', 'racing'));
  end loop;
  insert into race_rooms (code, host_id, created_at, expires_at, is_public)
  values (v_code, v_me, t,
          t + make_interval(mins => race_rule('lobby_minutes')),
          coalesce(p_public, false))
  returning id into v_room;
  insert into race_room_players (room_id, player_id, seat, joined_at, last_seen)
  values (v_room, v_me, 1, t, t);
  return race_state_json(v_room, v_me);
end $$;

-- The original private-lobby call keeps working.
create or replace function public.bm_create_room() returns jsonb
language sql volatile security definer set search_path = public as $$
  select public.bm_create_room(false)
$$;

create or replace function public.bm_join_room(p_code text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  v_code text := regexp_replace(coalesce(p_code, ''), '[\s-]', '', 'g');
  r race_rooms;
  v_seat int;
  t timestamptz := race_now();
begin
  if v_code !~ '^[0-9]{6}$' then return race_err('invalid_code'); end if;
  if not bm_rate_ok(v_me, 'join_room', 60, 600) then
    return race_err('rate_limited');
  end if;

  select * into r from race_rooms
    where code = v_code and status in ('lobby', 'countdown', 'racing')
    for update;
  if found then
    perform race_tick(r.id);
    select * into r from race_rooms where id = r.id;
  end if;

  if r.id is null or r.status not in ('lobby', 'countdown', 'racing') then
    if exists (select 1 from race_rooms where code = v_code) then
      return race_err('expired');
    end if;
    return race_err('not_found');
  end if;

  -- Rejoining your own seat is always allowed while the room is live.
  if exists (select 1 from race_room_players
             where room_id = r.id and player_id = v_me and left_at is null) then
    update race_room_players set last_seen = t
      where room_id = r.id and player_id = v_me;
    return race_state_json(r.id, v_me);
  end if;

  if r.status <> 'lobby' then return race_err('already_started'); end if;

  -- Blocks work both ways: neither side can share a lobby with the other.
  if exists (select 1 from race_room_players p
             where p.room_id = r.id and p.left_at is null
               and bm_is_blocked(v_me, p.player_id)) then
    return race_err('blocked');
  end if;

  delete from race_room_players
    where room_id = r.id and player_id = v_me and left_at is not null;

  select min(s) into v_seat
    from generate_series(1, race_rule('max_seats')) s
    where not exists (select 1 from race_room_players
                      where room_id = r.id and seat = s);
  if v_seat is null then return race_err('full'); end if;

  insert into race_room_players (room_id, player_id, seat, joined_at, last_seen)
  values (r.id, v_me, v_seat, t, t);
  delete from race_invites where room_id = r.id and to_id = v_me;
  return race_state_json(r.id, v_me);
end $$;

-- Quick race: the fullest open public lobby, or a new public one.
create or replace function public.bm_quick_join() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  v_live jsonb := bm_my_live_room();
  v_code text;
  t timestamptz := race_now();
begin
  if (v_live ->> 'ok')::boolean then return v_live; end if;
  select r.code into v_code
    from race_rooms r
    where r.status = 'lobby' and r.is_public and r.expires_at > t
      and (select count(*) from race_room_players p where p.room_id = r.id)
          < race_rule('max_seats')
      and not exists (select 1 from race_room_players p
                      where p.room_id = r.id and bm_is_blocked(v_me, p.player_id))
    order by (select count(*) from race_room_players p where p.room_id = r.id) desc,
             r.created_at
    limit 1;
  if v_code is not null then return bm_join_room(v_code); end if;
  return bm_create_room(true);
end $$;

create or replace function public.bm_set_ready(p_room uuid, p_ready boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  perform race_tick(p_room);
  if not exists (select 1 from race_rooms where id = p_room and status = 'lobby')
  then
    if not exists (select 1 from race_room_players
                   where room_id = p_room and player_id = v_me) then
      return race_err('not_member');
    end if;
    return race_err('already_started');
  end if;
  update race_room_players
    set ready = coalesce(p_ready, false), last_seen = race_now()
    where room_id = p_room and player_id = v_me and left_at is null;
  if not found then return race_err('not_member'); end if;
  return race_state_json(p_room, v_me);
end $$;

-- ---------------------------------------------------------------------------
-- Start: questions rotate so players rarely see repeats.
-- ---------------------------------------------------------------------------

create or replace function public.bm_start_race(p_room uuid) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  r race_rooms;
  v_ids text[];
  t timestamptz := race_now();
begin
  perform race_tick(p_room);
  select * into r from race_rooms where id = p_room for update;
  if not found then return race_err('not_found'); end if;
  if r.host_id <> v_me then return race_err('not_host'); end if;
  if r.status <> 'lobby' then return race_err('already_started'); end if;
  if (select count(*) from race_room_players where room_id = p_room)
       < race_rule('min_players') then
    return race_err('not_enough_players');
  end if;

  -- Least-recently-seen by this field first (last 14 days), random within.
  select array_agg(id order by random()) into v_ids
    from (select q.id from race_questions q
          where q.active
          order by (select count(*) from player_question_history h
                    join race_room_players p
                      on p.player_id = h.player_id and p.room_id = p_room
                    where h.question_id = q.id
                      and h.seen_at > t - interval '14 days'),
                   random()
          limit race_rule('max_questions')) s;
  if v_ids is null then return race_err('no_questions'); end if;

  update race_rooms
    set status = 'countdown',
        starts_at = t + make_interval(secs => race_rule('countdown_ms') / 1000.0),
        question_ids = v_ids, current_q = -1, q_resolved = false,
        questions_resolved = 0
    where id = p_room;
  insert into player_question_history (player_id, question_id, seen_at)
    select p.player_id, qid, t
    from race_room_players p, unnest(v_ids) qid
    where p.room_id = p_room
  on conflict (player_id, question_id) do update set seen_at = excluded.seen_at;
  delete from race_invites where room_id = p_room;
  return race_state_json(p_room, v_me);
end $$;

-- ---------------------------------------------------------------------------
-- Friends: blocks and rate limits
-- ---------------------------------------------------------------------------

create or replace function public.bm_send_friend_request(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  v_other uuid;
begin
  if not bm_rate_ok(v_me, 'friend_request', 30, 3600) then
    return race_err('rate_limited');
  end if;
  select id into v_other from player_profiles
    where friend_code = upper(btrim(coalesce(p_code, '')));
  if v_other is null then return race_err('not_found'); end if;
  if v_other = v_me then return race_err('self'); end if;
  -- Do not reveal a block to the blocked player.
  if bm_is_blocked(v_me, v_other) then return race_err('not_found'); end if;
  if exists (select 1 from friend_links where status = 'accepted' and
             ((requester = v_me and addressee = v_other) or
              (requester = v_other and addressee = v_me))) then
    return race_err('already_friends');
  end if;
  -- They already asked us: accept instead.
  if exists (select 1 from friend_links where requester = v_other
             and addressee = v_me and status = 'pending') then
    update friend_links set status = 'accepted'
      where requester = v_other and addressee = v_me;
    return jsonb_build_object('ok', true, 'status', 'accepted');
  end if;
  insert into friend_links (requester, addressee, status)
  values (v_me, v_other, 'pending') on conflict do nothing;
  return jsonb_build_object('ok', true, 'status', 'pending');
end $$;

create or replace function public.bm_invite_friend(p_room uuid, p_friend uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  if not exists (select 1 from race_room_players
                 where room_id = p_room and player_id = v_me and left_at is null)
  then
    return race_err('not_member');
  end if;
  if not exists (select 1 from race_rooms where id = p_room and status = 'lobby')
  then
    return race_err('already_started');
  end if;
  if not exists (select 1 from friend_links where status = 'accepted' and
                 ((requester = v_me and addressee = p_friend) or
                  (requester = p_friend and addressee = v_me))) then
    return race_err('not_friends');
  end if;
  if not bm_rate_ok(v_me, 'invite', 60, 3600) then
    return race_err('rate_limited');
  end if;
  insert into race_invites (room_id, from_id, to_id)
  values (p_room, v_me, p_friend)
  on conflict (room_id, to_id) do update set created_at = now(),
                                            from_id = excluded.from_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.bm_block_player(p_player uuid) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  if p_player is null or p_player = v_me then return race_err('self'); end if;
  if not exists (select 1 from player_profiles where id = p_player) then
    return race_err('not_found');
  end if;
  insert into player_blocks (blocker, blocked) values (v_me, p_player)
    on conflict do nothing;
  delete from friend_links
    where (requester = v_me and addressee = p_player)
       or (requester = p_player and addressee = v_me);
  delete from race_invites
    where (from_id = v_me and to_id = p_player)
       or (from_id = p_player and to_id = v_me);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.bm_unblock_player(p_player uuid) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  delete from player_blocks where blocker = v_me and blocked = p_player;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.bm_blocked_players() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  return jsonb_build_object('ok', true, 'players', coalesce((
    select jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.display_name,
                                        'color', pr.color_index)
                     order by b.created_at desc)
    from player_blocks b join player_profiles pr on pr.id = b.blocked
    where b.blocker = v_me), '[]'));
end $$;

-- ---------------------------------------------------------------------------
-- Reports and question moderation
-- ---------------------------------------------------------------------------

create or replace function public.bm_report_player(
  p_target uuid, p_reason text, p_details text default null,
  p_room uuid default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  if p_target is null or p_target = v_me then return race_err('self'); end if;
  if not exists (select 1 from player_profiles where id = p_target) then
    return race_err('not_found');
  end if;
  if p_reason is null or p_reason not in
     ('offensive_name', 'cheating', 'harassment', 'other') then
    return race_err('invalid_reason');
  end if;
  -- A room is only recorded when both players were in it.
  if p_room is not null and (select count(*) from race_room_players
      where room_id = p_room and player_id in (v_me, p_target)) < 2 then
    p_room := null;
  end if;
  if exists (select 1 from player_reports where reporter = v_me
             and target = p_target and status = 'open') then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;
  if not bm_rate_ok(v_me, 'report', 10, 86400) then
    return race_err('rate_limited');
  end if;
  insert into player_reports (reporter, target, room_id, reason, details)
  values (v_me, p_target, p_room, p_reason, left(btrim(p_details), 280));
  return jsonb_build_object('ok', true, 'duplicate', false);
end $$;

-- Players report a question they were shown, by its number in the race; the
-- question id never reaches the client. Three distinct reports flag it for
-- review (it stays in rotation until a moderator decides).
create or replace function public.bm_report_question(
  p_room uuid, p_question int, p_reason text, p_details text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  r race_rooms;
  v_qid text;
begin
  select * into r from race_rooms where id = p_room;
  if not found or not exists (select 1 from race_room_players
                              where room_id = p_room and player_id = v_me) then
    return race_err('not_member');
  end if;
  if p_question is null or p_question < 0 or p_question > r.current_q
     or r.status in ('lobby', 'countdown') then
    return race_err('wrong_question');
  end if;
  if p_reason is null or p_reason not in
     ('wrong_answer', 'unclear', 'offensive', 'other') then
    return race_err('invalid_reason');
  end if;
  v_qid := r.question_ids[p_question + 1];
  if exists (select 1 from question_reports
             where reporter = v_me and question_id = v_qid) then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;
  if not bm_rate_ok(v_me, 'report', 10, 86400) then
    return race_err('rate_limited');
  end if;
  insert into question_reports (reporter, question_id, room_id, reason, details)
  values (v_me, v_qid, p_room, p_reason, left(btrim(p_details), 280));
  update race_questions set needs_review = true
    where id = v_qid
      and (select count(*) from question_reports where question_id = v_qid) >= 3;
  return jsonb_build_object('ok', true, 'duplicate', false);
end $$;

-- ---------------------------------------------------------------------------
-- Rankings: all time, this week, this month (UTC)
-- ---------------------------------------------------------------------------

create or replace function public.bm_leaderboard_period(
  p_period text, p_limit int default 50)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_from timestamptz := case p_period
    when 'week' then date_trunc('week', race_now() at time zone 'UTC') at time zone 'UTC'
    when 'month' then date_trunc('month', race_now() at time zone 'UTC') at time zone 'UTC'
    when 'all' then '-infinity'::timestamptz end;
begin
  if v_from is null then return race_err('invalid_period'); end if;
  return jsonb_build_object('ok', true, 'period', p_period, 'rows', coalesce((
    select jsonb_agg(row_to_json(x)::jsonb order by x.rank)
    from (
      select rank() over (order by s.wins desc, s.podiums desc, s.races desc)
               as rank,
             s.player_id as id, pr.display_name as name,
             pr.color_index as color, s.wins, s.podiums, s.races,
             s.player_id = v_me as is_me
      from (select player_id,
                   count(*) filter (where finish_place = 1) as wins,
                   count(*) filter (where finish_place <= 3) as podiums,
                   count(*) as races
            from race_results
            where recorded_at >= v_from
            group by player_id) s
      join player_profiles pr on pr.id = s.player_id
      order by s.wins desc, s.podiums desc, s.races desc
      limit least(greatest(coalesce(p_limit, 50), 1), 200)
    ) x), '[]'));
end $$;

-- ---------------------------------------------------------------------------
-- Notifications and race history
-- ---------------------------------------------------------------------------

create or replace function public.bm_notifications(p_limit int default 30)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  delete from player_notifications
    where player_id = v_me and created_at < race_now() - interval '30 days';
  return jsonb_build_object(
    'ok', true,
    'unread', (select count(*) from player_notifications
               where player_id = v_me and read_at is null),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind,
                                          'payload', n.payload,
                                          'created_at', n.created_at,
                                          'read', n.read_at is not null)
                       order by n.id desc)
      from (select * from player_notifications where player_id = v_me
            order by id desc
            limit least(greatest(coalesce(p_limit, 30), 1), 100)) n), '[]'));
end $$;

create or replace function public.bm_mark_notifications_read() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  update player_notifications set read_at = race_now()
    where player_id = v_me and read_at is null;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.bm_race_history(p_limit int default 20)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  return jsonb_build_object('ok', true, 'races', coalesce((
    select jsonb_agg(jsonb_build_object(
             'room_id', rr.room_id, 'placing', rr.finish_place,
             'field', (select count(*) from race_results x
                       where x.room_id = rr.room_id),
             'progress', rr.progress, 'finished', rr.finished,
             'eliminated', rr.eliminated, 'correct', rr.correct,
             'answered', rr.answered, 'recorded_at', rr.recorded_at)
           order by rr.recorded_at desc)
    from (select * from race_results where player_id = v_me
          order by recorded_at desc
          limit least(greatest(coalesce(p_limit, 20), 1), 100)) rr), '[]'));
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke execute on function
  public.bm_is_blocked(uuid, uuid), public.bm_rate_ok(uuid, text, int, int),
  public.bm_notify(uuid, text, jsonb), public.race_signal(uuid),
  public.race_rooms_signal(), public.race_seats_signal(),
  public.race_notify_friend(), public.race_notify_invite(),
  public.race_notify_result(),
  public.bm_create_room(boolean), public.bm_quick_join(),
  public.bm_set_ready(uuid, boolean), public.bm_block_player(uuid),
  public.bm_unblock_player(uuid), public.bm_blocked_players(),
  public.bm_report_player(uuid, text, text, uuid),
  public.bm_report_question(uuid, int, text, text),
  public.bm_leaderboard_period(text, int), public.bm_notifications(int),
  public.bm_mark_notifications_read(), public.bm_race_history(int)
from public, anon;
-- The RLS policy on race_room_signals calls this as the querying user.
revoke execute on function public.bm_is_room_member(uuid) from public, anon;
grant execute on function public.bm_is_room_member(uuid) to authenticated;
grant execute on function
  public.bm_create_room(boolean), public.bm_quick_join(),
  public.bm_set_ready(uuid, boolean), public.bm_block_player(uuid),
  public.bm_unblock_player(uuid), public.bm_blocked_players(),
  public.bm_report_player(uuid, text, text, uuid),
  public.bm_report_question(uuid, int, text, text),
  public.bm_leaderboard_period(text, int), public.bm_notifications(int),
  public.bm_mark_notifications_read(), public.bm_race_history(int)
to authenticated;

-- ---------------------------------------------------------------------------
-- Question bank: fix a typo, and double the bank so rotation has room.
-- ---------------------------------------------------------------------------

update public.race_questions
  set prompt = 'What is "app" short for?'
  where id = 'q023' and prompt = 'What does "app" short for?';

insert into public.race_questions (id, category, difficulty, prompt, options, correct_index) values
  ('q031', 'Science', 'Easy', 'What is the boiling point of water at sea level in Celsius?', array['90°C', '100°C', '110°C', '120°C'], 1),
  ('q032', 'Geography', 'Medium', 'Which is the longest river in South America?', array['Paraná', 'Orinoco', 'Amazon', 'Magdalena'], 2),
  ('q033', 'Space', 'Easy', 'Which planet is closest to the Sun?', array['Venus', 'Mercury', 'Mars', 'Earth'], 1),
  ('q034', 'History', 'Easy', 'Who was the first person to walk on the Moon?', array['Buzz Aldrin', 'Yuri Gagarin', 'Neil Armstrong', 'John Glenn'], 2),
  ('q035', 'Music', 'Medium', 'How many keys does a standard piano have?', array['76', '82', '88', '92'], 2),
  ('q036', 'Animals', 'Easy', 'How many legs does a spider have?', array['Six', 'Eight', 'Ten', 'Twelve'], 1),
  ('q037', 'Mathematics', 'Easy', 'What is 12 multiplied by 12?', array['124', '132', '144', '156'], 2),
  ('q038', 'Technology', 'Easy', 'What does "CPU" stand for?', array['Central Processing Unit', 'Computer Power Unit', 'Core Program Utility', 'Central Peripheral Unit'], 0),
  ('q039', 'Literature', 'Medium', 'Who wrote "Pride and Prejudice"?', array['Charlotte Brontë', 'Jane Austen', 'George Eliot', 'Mary Shelley'], 1),
  ('q040', 'Food', 'Easy', 'Which country is the origin of sushi?', array['China', 'Korea', 'Japan', 'Thailand'], 2),
  ('q041', 'Sport', 'Easy', 'How many rings are on the Olympic flag?', array['Four', 'Five', 'Six', 'Seven'], 1),
  ('q042', 'World Capitals', 'Easy', 'What is the capital of Japan?', array['Osaka', 'Kyoto', 'Tokyo', 'Nagoya'], 2),
  ('q043', 'Nature', 'Medium', 'What is the hardest natural substance?', array['Quartz', 'Diamond', 'Granite', 'Topaz'], 1),
  ('q044', 'Movies', 'Easy', 'In which film does a clownfish named Nemo go missing?', array['Shark Tale', 'Finding Nemo', 'The Little Mermaid', 'Moana'], 1),
  ('q045', 'Mythology', 'Medium', 'Who is the king of the gods in Norse mythology?', array['Thor', 'Loki', 'Odin', 'Freyr'], 2),
  ('q046', 'Geography', 'Medium', 'Which desert is the largest hot desert in the world?', array['Gobi', 'Kalahari', 'Sahara', 'Arabian'], 2),
  ('q047', 'British Culture', 'Easy', 'Which river flows through London?', array['Severn', 'Thames', 'Trent', 'Mersey'], 1),
  ('q048', 'Science', 'Medium', 'What part of the cell contains its genetic material?', array['Nucleus', 'Ribosome', 'Membrane', 'Mitochondrion'], 0),
  ('q049', 'Art', 'Easy', 'Who painted the "Mona Lisa"?', array['Vincent van Gogh', 'Leonardo da Vinci', 'Pablo Picasso', 'Claude Monet'], 1),
  ('q050', 'Video Games', 'Easy', 'What colour is Sonic the Hedgehog?', array['Red', 'Green', 'Blue', 'Yellow'], 2),
  ('q051', 'General Knowledge', 'Easy', 'How many days are in a leap year?', array['364', '365', '366', '367'], 2),
  ('q052', 'History', 'Hard', 'In which year did the Titanic sink?', array['1905', '1912', '1918', '1921'], 1),
  ('q053', 'Technology', 'Hard', 'In computing, how many bits are in a byte?', array['Four', 'Eight', 'Sixteen', 'Thirty-two'], 1),
  ('q054', 'Television', 'Easy', 'Which colour is the TARDIS police box in "Doctor Who"?', array['Red', 'Green', 'Blue', 'Black'], 2),
  ('q055', 'Space', 'Medium', 'What is the largest planet in our solar system?', array['Saturn', 'Jupiter', 'Neptune', 'Uranus'], 1),
  ('q056', 'Animals', 'Hard', 'What is a group of crows called?', array['A pride', 'A murder', 'A pod', 'A gaggle'], 1),
  ('q057', 'Mathematics', 'Hard', 'What is the square root of 169?', array['11', '12', '13', '14'], 2),
  ('q058', 'Sport', 'Medium', 'In tennis, what is a score of zero called?', array['Nil', 'Love', 'Duck', 'Zip'], 1),
  ('q059', 'Food', 'Hard', 'Which nut is used to make marzipan?', array['Hazelnut', 'Walnut', 'Almond', 'Cashew'], 2),
  ('q060', 'Geography', 'Hard', 'What is the smallest country in the world by area?', array['Monaco', 'San Marino', 'Vatican City', 'Liechtenstein'], 2)
on conflict (id) do nothing;
