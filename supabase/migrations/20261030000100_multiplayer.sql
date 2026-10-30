-- Buzz Masters — server-authoritative online Turbo Trivia Race.
--
-- For a DEDICATED Buzz Masters Supabase project only.
--
-- Clients never write race state. Every action is a SECURITY DEFINER RPC that
-- checks the caller (auth.uid()), and every table has RLS on with no client
-- policies, so the tables themselves are unreadable from the API. Correct
-- answers live only here; clients receive question text and options.
--
-- Time is the database clock. The race advances lazily: every state read and
-- answer calls race_tick(), which applies whatever transitions are due
-- (countdown → racing, question timeout → reveal → next question → finish)
-- under a row lock, so concurrent players always see one consistent race.
--
-- Rules mirror lib/bm/race/race_model.dart with kTurboRaceConfig.

-- ---------------------------------------------------------------------------
-- Clock and rules
-- ---------------------------------------------------------------------------

create or replace function public.race_now() returns timestamptz
language sql volatile as $$ select clock_timestamp() $$;

create or replace function public.race_rule(p_name text) returns int
language sql immutable as $$
  select case p_name
    when 'distance' then 100
    when 'correct_gain' then 10
    when 'fast_gain' then 15
    when 'fast_ms' then 3000
    when 'wrong_penalty' then 5
    when 'timeout_penalty' then 3
    when 'danger_max' then 10
    when 'danger_grace' then 1
    when 'danger_free' then 3
    when 'window_ms' then 8000
    when 'reveal_ms' then 1500
    when 'countdown_ms' then 3000
    when 'max_questions' then 30
    when 'max_seats' then 6
    when 'min_players' then 2
    when 'lobby_minutes' then 30
    when 'stale_seconds' then 20
  end
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.player_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Racer'
    check (char_length(display_name) between 1 and 16),
  color_index int not null default 1 check (color_index between 0 and 5),
  friend_code text not null unique check (friend_code ~ '^[A-Z0-9]{6}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.race_questions (
  id text primary key,
  category text not null,
  difficulty text not null,
  prompt text not null,
  options text[] not null check (array_length(options, 1) between 2 and 6),
  correct_index int not null,
  active boolean not null default true,
  check (correct_index >= 0 and correct_index < array_length(options, 1))
);

create table if not exists public.race_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null check (code ~ '^[0-9]{6}$'),
  host_id uuid not null references public.player_profiles (id) on delete cascade,
  status text not null default 'lobby'
    check (status in ('lobby', 'countdown', 'racing', 'finished', 'abandoned')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  starts_at timestamptz,
  question_ids text[] not null default '{}',
  current_q int not null default -1,
  q_opened_at timestamptz,
  q_resolved boolean not null default false,
  questions_resolved int not null default 0,
  last_correct_index int,
  finished_at timestamptz
);

-- A code identifies at most one live room at a time.
create unique index if not exists race_rooms_live_code
  on public.race_rooms (code)
  where status in ('lobby', 'countdown', 'racing');
create index if not exists race_rooms_code_recent
  on public.race_rooms (code, created_at desc);

create table if not exists public.race_room_players (
  room_id uuid not null references public.race_rooms (id) on delete cascade,
  player_id uuid not null references public.player_profiles (id) on delete cascade,
  seat int not null check (seat between 1 and 6),
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  left_at timestamptz,
  progress int not null default 0,
  finished_ms int,
  eliminated boolean not null default false,
  danger_streak int not null default 0,
  speed text not null default 'stopped'
    check (speed in ('stopped', 'cruising', 'fast')),
  correct int not null default 0,
  answered int not null default 0,
  primary key (room_id, player_id),
  unique (room_id, seat)
);
create index if not exists race_room_players_player
  on public.race_room_players (player_id);

-- One row per player per question: the primary key is what makes a second
-- answer to the same question impossible.
create table if not exists public.race_answers (
  room_id uuid not null,
  player_id uuid not null,
  q_index int not null,
  option_index int,
  correct boolean not null,
  response_ms int,
  delta int not null,
  answered_at timestamptz not null,
  primary key (room_id, player_id, q_index),
  foreign key (room_id, player_id)
    references public.race_room_players (room_id, player_id) on delete cascade
);

create table if not exists public.race_results (
  room_id uuid not null references public.race_rooms (id) on delete cascade,
  player_id uuid not null references public.player_profiles (id) on delete cascade,
  finish_place int not null,
  progress int not null,
  finished boolean not null,
  eliminated boolean not null,
  correct int not null,
  answered int not null,
  recorded_at timestamptz not null default now(),
  primary key (room_id, player_id)
);
create index if not exists race_results_player on public.race_results (player_id);

create table if not exists public.friend_links (
  requester uuid not null references public.player_profiles (id) on delete cascade,
  addressee uuid not null references public.player_profiles (id) on delete cascade,
  status text not null check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);
create index if not exists friend_links_addressee on public.friend_links (addressee);

create table if not exists public.race_invites (
  room_id uuid not null references public.race_rooms (id) on delete cascade,
  from_id uuid not null references public.player_profiles (id) on delete cascade,
  to_id uuid not null references public.player_profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (room_id, to_id)
);
create index if not exists race_invites_to on public.race_invites (to_id);

-- Deny all direct table access; the RPCs below are the only API.
alter table public.player_profiles enable row level security;
alter table public.race_questions enable row level security;
alter table public.race_rooms enable row level security;
alter table public.race_room_players enable row level security;
alter table public.race_answers enable row level security;
alter table public.race_results enable row level security;
alter table public.friend_links enable row level security;
alter table public.race_invites enable row level security;
revoke all on public.player_profiles, public.race_questions, public.race_rooms,
  public.race_room_players, public.race_answers, public.race_results,
  public.friend_links, public.race_invites from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Internal helpers (not callable by clients)
-- ---------------------------------------------------------------------------

create or replace function public.race_err(p_code text) returns jsonb
language sql immutable as $$ select jsonb_build_object('ok', false, 'error', p_code) $$;

create or replace function public.race_me() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  v uuid := auth.uid();
begin
  if v is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not exists (select 1 from player_profiles where id = v) then
    raise exception 'no_profile' using errcode = 'P0002';
  end if;
  return v;
end $$;

create or replace function public.race_new_friend_code() returns text
language plpgsql volatile set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v text;
begin
  loop
    v := '';
    for i in 1..6 loop
      v := v || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from player_profiles where friend_code = v);
  end loop;
  return v;
end $$;

-- Writes final placings once, when a race ends.
create or replace function public.race_record_results(p_room uuid) returns void
language plpgsql volatile set search_path = public as $$
begin
  insert into race_results (room_id, player_id, finish_place, progress, finished,
                            eliminated, correct, answered)
  select room_id, player_id,
         row_number() over (order by
           (finished_ms is null),
           finished_ms nulls last,
           eliminated,
           progress desc,
           seat),
         progress, finished_ms is not null, eliminated, correct, answered
  from race_room_players
  where room_id = p_room
  on conflict do nothing;
end $$;

-- Applies every transition that is due. Caller must not hold other locks on
-- the room in a conflicting order; this takes the row lock itself.
create or replace function public.race_tick(p_room uuid) returns void
language plpgsql volatile set search_path = public as $$
declare
  r race_rooms;
  t timestamptz := race_now();
  v_window interval := make_interval(secs => race_rule('window_ms') / 1000.0);
  v_active int;
  v_unanswered int;
  v_done boolean;
  v_correct int;
  guard int := 0;
begin
  select * into r from race_rooms where id = p_room for update;
  if not found then return; end if;

  loop
    guard := guard + 1;
    exit when guard > 4;

    if r.status = 'lobby' then
      if t >= r.expires_at then
        update race_rooms set status = 'abandoned' where id = p_room;
      end if;
      exit;
    end if;

    if r.status = 'countdown' then
      exit when t < r.starts_at;
      update race_rooms
        set status = 'racing', current_q = 0, q_opened_at = r.starts_at,
            q_resolved = false
        where id = p_room returning * into r;
      continue;
    end if;

    exit when r.status <> 'racing';

    -- Everyone who has left: the race is abandoned.
    if not exists (select 1 from race_room_players
                   where room_id = p_room and left_at is null) then
      update race_rooms set status = 'abandoned', finished_at = t where id = p_room;
      exit;
    end if;

    exit when t < r.q_opened_at;

    select count(*) filter (where finished_ms is null and not eliminated),
           count(*) filter (where finished_ms is null and not eliminated
             and not exists (select 1 from race_answers a
                             where a.room_id = p.room_id
                               and a.player_id = p.player_id
                               and a.q_index = r.current_q))
      into v_active, v_unanswered
      from race_room_players p
      where p.room_id = p_room;

    exit when t < r.q_opened_at + v_window and v_unanswered > 0;

    -- Resolve: timeouts for anyone still silent (including disconnected).
    insert into race_answers (room_id, player_id, q_index, option_index,
                              correct, response_ms, delta, answered_at)
    select p.room_id, p.player_id, r.current_q, null, false, null,
           -least(p.progress, race_rule('timeout_penalty')), t
    from race_room_players p
    where p.room_id = p_room and p.finished_ms is null and not p.eliminated
      and not exists (select 1 from race_answers a
                      where a.room_id = p.room_id and a.player_id = p.player_id
                        and a.q_index = r.current_q);
    update race_room_players p
      set progress = greatest(0, p.progress - race_rule('timeout_penalty')),
          speed = 'stopped'
    where p.room_id = p_room and p.finished_ms is null and not p.eliminated
      and exists (select 1 from race_answers a
                  where a.room_id = p.room_id and a.player_id = p.player_id
                    and a.q_index = r.current_q and a.option_index is null
                    and a.answered_at = t);

    -- Danger zone, after the safe start.
    if r.questions_resolved >= race_rule('danger_free') then
      update race_room_players
        set danger_streak = case when progress <= race_rule('danger_max')
                                 then danger_streak + 1 else 0 end,
            eliminated = progress <= race_rule('danger_max')
                         and danger_streak + 1 > race_rule('danger_grace')
      where room_id = p_room and finished_ms is null and not eliminated;
    end if;

    select q.correct_index into v_correct
      from race_questions q where q.id = r.question_ids[r.current_q + 1];

    v_done := exists (select 1 from race_room_players
                      where room_id = p_room and finished_ms is not null)
           or not exists (select 1 from race_room_players
                          where room_id = p_room and finished_ms is null
                            and not eliminated)
           or r.questions_resolved + 1 >= least(race_rule('max_questions'),
                                                 cardinality(r.question_ids));

    if v_done then
      update race_rooms
        set status = 'finished', finished_at = t, q_resolved = true,
            questions_resolved = r.questions_resolved + 1,
            last_correct_index = v_correct
        where id = p_room;
      perform race_record_results(p_room);
      exit;
    end if;

    -- Next question opens after the reveal pause.
    update race_rooms
      set current_q = r.current_q + 1,
          q_opened_at = t + make_interval(secs => race_rule('reveal_ms') / 1000.0),
          q_resolved = false,
          questions_resolved = r.questions_resolved + 1,
          last_correct_index = v_correct
      where id = p_room returning * into r;
  end loop;
end $$;

-- The full view of a room for one member.
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
    'host_id', r.host_id,
    'is_host', r.host_id = p_me,
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
-- Client API
-- ---------------------------------------------------------------------------

create or replace function public.bm_upsert_profile(p_name text, p_color int)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v uuid := auth.uid();
  v_name text := left(btrim(coalesce(p_name, '')), 16);
  p player_profiles;
begin
  if v is null then return race_err('not_authenticated'); end if;
  if v_name = '' then v_name := 'Racer'; end if;
  insert into player_profiles (id, display_name, color_index, friend_code)
  values (v, v_name, least(5, greatest(0, coalesce(p_color, 1))),
          race_new_friend_code())
  on conflict (id) do update
    set display_name = excluded.display_name,
        color_index = excluded.color_index
  returning * into p;
  return jsonb_build_object('ok', true, 'id', p.id, 'name', p.display_name,
                            'color', p.color_index,
                            'friend_code', p.friend_code);
end $$;

create or replace function public.bm_create_room() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  v_code text;
  v_room uuid;
  t timestamptz := race_now();
begin
  loop
    v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from race_rooms where code = v_code
                          and status in ('lobby', 'countdown', 'racing'));
  end loop;
  insert into race_rooms (code, host_id, created_at, expires_at)
  values (v_code, v_me, t,
          t + make_interval(mins => race_rule('lobby_minutes')))
  returning id into v_room;
  insert into race_room_players (room_id, player_id, seat, joined_at, last_seen)
  values (v_room, v_me, 1, t, t);
  return race_state_json(v_room, v_me);
end $$;

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

create or replace function public.bm_room_state(p_room uuid) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  if not exists (select 1 from race_room_players
                 where room_id = p_room and player_id = v_me) then
    return race_err('not_member');
  end if;
  perform race_tick(p_room);
  update race_room_players set last_seen = race_now()
    where room_id = p_room and player_id = v_me and left_at is null;
  return race_state_json(p_room, v_me);
end $$;

-- The caller's live room, for "Resume last session".
create or replace function public.bm_my_live_room() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  v_room uuid;
begin
  for v_room in
    select p.room_id from race_room_players p
    join race_rooms r on r.id = p.room_id
    where p.player_id = v_me and p.left_at is null
      and r.status in ('lobby', 'countdown', 'racing')
    order by p.joined_at desc
  loop
    perform race_tick(v_room);
    if exists (select 1 from race_rooms where id = v_room
               and status in ('lobby', 'countdown', 'racing')) then
      return race_state_json(v_room, v_me);
    end if;
  end loop;
  return race_err('none');
end $$;

create or replace function public.bm_leave_room(p_room uuid) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  r race_rooms;
  v_next uuid;
begin
  select * into r from race_rooms where id = p_room for update;
  if not found or not exists (select 1 from race_room_players
                              where room_id = p_room and player_id = v_me) then
    return race_err('not_member');
  end if;

  if r.status = 'lobby' then
    delete from race_room_players where room_id = p_room and player_id = v_me;
    if r.host_id = v_me then
      select player_id into v_next from race_room_players
        where room_id = p_room order by seat limit 1;
      if v_next is null then
        update race_rooms set status = 'abandoned' where id = p_room;
      else
        update race_rooms set host_id = v_next where id = p_room;
      end if;
    end if;
  elsif r.status in ('countdown', 'racing') then
    -- Leaving a race forfeits it; the others race on.
    update race_room_players set left_at = race_now(), eliminated = true,
                                 speed = 'stopped'
      where room_id = p_room and player_id = v_me and left_at is null;
    perform race_tick(p_room);
  end if;
  return jsonb_build_object('ok', true);
end $$;

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

  select array_agg(id order by random()) into v_ids
    from (select id from race_questions where active
          order by random() limit race_rule('max_questions')) s;
  if v_ids is null then return race_err('no_questions'); end if;

  update race_rooms
    set status = 'countdown',
        starts_at = t + make_interval(secs => race_rule('countdown_ms') / 1000.0),
        question_ids = v_ids, current_q = -1, q_resolved = false,
        questions_resolved = 0
    where id = p_room;
  delete from race_invites where room_id = p_room;
  return race_state_json(p_room, v_me);
end $$;

create or replace function public.bm_submit_answer(
  p_room uuid, p_question int, p_option int)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  r race_rooms;
  p race_room_players;
  q race_questions;
  t timestamptz;
  v_ms int;
  v_correct boolean;
  v_delta int;
  v_progress int;
begin
  perform race_tick(p_room);
  select * into r from race_rooms where id = p_room for update;
  t := race_now();
  select * into p from race_room_players
    where room_id = p_room and player_id = v_me for update;
  if not found then return race_err('not_member'); end if;
  if r.status <> 'racing' then return race_err('not_racing'); end if;
  if p.left_at is not null or p.eliminated or p.finished_ms is not null then
    return race_err('not_active');
  end if;
  if p_question <> r.current_q or r.q_resolved or t < r.q_opened_at then
    return race_err('wrong_question');
  end if;
  v_ms := (extract(epoch from (t - r.q_opened_at)) * 1000)::int;
  if v_ms >= race_rule('window_ms') then return race_err('too_late'); end if;

  select * into q from race_questions where id = r.question_ids[r.current_q + 1];
  if p_option is null or p_option < 0
     or p_option >= array_length(q.options, 1) then
    return race_err('invalid_option');
  end if;

  v_correct := p_option = q.correct_index;
  v_delta := case
    when v_correct and v_ms <= race_rule('fast_ms') then race_rule('fast_gain')
    when v_correct then race_rule('correct_gain')
    else -race_rule('wrong_penalty') end;
  v_progress := least(race_rule('distance'), greatest(0, p.progress + v_delta));

  insert into race_answers (room_id, player_id, q_index, option_index, correct,
                            response_ms, delta, answered_at)
  values (p_room, v_me, r.current_q, p_option, v_correct, v_ms,
          v_progress - p.progress, t)
  on conflict do nothing;
  if not found then return race_err('duplicate'); end if;

  update race_room_players
    set progress = v_progress,
        speed = case when not v_correct then 'stopped'
                     when v_ms <= race_rule('fast_ms') then 'fast'
                     else 'cruising' end,
        correct = correct + (case when v_correct then 1 else 0 end),
        answered = answered + 1,
        last_seen = t,
        finished_ms = case when v_progress >= race_rule('distance')
          then (extract(epoch from (t - r.starts_at)) * 1000)::int end
    where room_id = p_room and player_id = v_me;

  perform race_tick(p_room);
  return jsonb_build_object('ok', true, 'correct', v_correct,
                            'delta', v_progress - p.progress,
                            'progress', v_progress, 'response_ms', v_ms);
end $$;

-- Friends --------------------------------------------------------------------

create or replace function public.bm_send_friend_request(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  v_other uuid;
begin
  select id into v_other from player_profiles
    where friend_code = upper(btrim(coalesce(p_code, '')));
  if v_other is null then return race_err('not_found'); end if;
  if v_other = v_me then return race_err('self'); end if;
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

create or replace function public.bm_respond_friend_request(
  p_requester uuid, p_accept boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  if p_accept then
    update friend_links set status = 'accepted'
      where requester = p_requester and addressee = v_me and status = 'pending';
  else
    delete from friend_links
      where requester = p_requester and addressee = v_me and status = 'pending';
  end if;
  if not found then return race_err('not_found'); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.bm_remove_friend(p_friend uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
begin
  delete from friend_links
    where (requester = v_me and addressee = p_friend)
       or (requester = p_friend and addressee = v_me);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.bm_friends() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me uuid := race_me();
  t timestamptz := race_now();
begin
  return jsonb_build_object(
    'ok', true,
    'my_code', (select friend_code from player_profiles where id = v_me),
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.display_name,
                                          'color', pr.color_index)
                       order by pr.display_name)
      from friend_links f
      join player_profiles pr
        on pr.id = case when f.requester = v_me then f.addressee else f.requester end
      where f.status = 'accepted' and v_me in (f.requester, f.addressee)), '[]'),
    'incoming', coalesce((
      select jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.display_name,
                                          'color', pr.color_index))
      from friend_links f join player_profiles pr on pr.id = f.requester
      where f.addressee = v_me and f.status = 'pending'), '[]'),
    'outgoing', coalesce((
      select jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.display_name,
                                          'color', pr.color_index))
      from friend_links f join player_profiles pr on pr.id = f.addressee
      where f.requester = v_me and f.status = 'pending'), '[]'),
    'invites', coalesce((
      select jsonb_agg(jsonb_build_object('room_id', r.id, 'code', r.code,
                                          'from', pr.display_name,
                                          'from_id', pr.id)
                       order by i.created_at desc)
      from race_invites i
      join race_rooms r on r.id = i.room_id
      join player_profiles pr on pr.id = i.from_id
      where i.to_id = v_me and r.status = 'lobby' and r.expires_at > t), '[]'));
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
  insert into race_invites (room_id, from_id, to_id)
  values (p_room, v_me, p_friend)
  on conflict (room_id, to_id) do update set created_at = now(),
                                            from_id = excluded.from_id;
  return jsonb_build_object('ok', true);
end $$;

-- Leaderboard ---------------------------------------------------------------

create or replace function public.bm_leaderboard(p_limit int default 50)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  return jsonb_build_object('ok', true, 'rows', coalesce((
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
            from race_results group by player_id) s
      join player_profiles pr on pr.id = s.player_id
      order by s.wins desc, s.podiums desc, s.races desc
      limit least(greatest(coalesce(p_limit, 50), 1), 200)
    ) x), '[]'));
end $$;

-- ---------------------------------------------------------------------------
-- Grants: only the client API is executable, and only when signed in.
-- ---------------------------------------------------------------------------

-- Scoped to this migration's functions: the monetisation migration relies
-- on the default PUBLIC execute grant and must not be affected.
revoke execute on function
  public.race_now(), public.race_rule(text), public.race_err(text),
  public.race_me(), public.race_new_friend_code(),
  public.race_record_results(uuid), public.race_tick(uuid),
  public.race_state_json(uuid, uuid),
  public.bm_upsert_profile(text, int), public.bm_create_room(),
  public.bm_join_room(text), public.bm_room_state(uuid),
  public.bm_my_live_room(), public.bm_leave_room(uuid),
  public.bm_start_race(uuid), public.bm_submit_answer(uuid, int, int),
  public.bm_send_friend_request(text),
  public.bm_respond_friend_request(uuid, boolean),
  public.bm_remove_friend(uuid), public.bm_friends(),
  public.bm_invite_friend(uuid, uuid), public.bm_leaderboard(int)
from public, anon;
grant execute on function
  public.bm_upsert_profile(text, int),
  public.bm_create_room(),
  public.bm_join_room(text),
  public.bm_room_state(uuid),
  public.bm_my_live_room(),
  public.bm_leave_room(uuid),
  public.bm_start_race(uuid),
  public.bm_submit_answer(uuid, int, int),
  public.bm_send_friend_request(text),
  public.bm_respond_friend_request(uuid, boolean),
  public.bm_remove_friend(uuid),
  public.bm_friends(),
  public.bm_invite_friend(uuid, uuid),
  public.bm_leaderboard(int)
to authenticated;


-- ---------------------------------------------------------------------------
-- Question bank (server-only answers)
-- ---------------------------------------------------------------------------
insert into public.race_questions (id, category, difficulty, prompt, options, correct_index) values
  ('q001', 'Science', 'Easy', 'Which planet is known as the Red Planet?', array['Earth', 'Mars', 'Jupiter', 'Venus'], 1),
  ('q002', 'Geography', 'Easy', 'What is the capital of France?', array['Berlin', 'Madrid', 'Paris', 'Rome'], 2),
  ('q003', 'Space', 'Medium', 'Which planet has the most moons?', array['Jupiter', 'Saturn', 'Uranus', 'Neptune'], 1),
  ('q004', 'History', 'Medium', 'In which year did the Berlin Wall fall?', array['1987', '1989', '1991', '1993'], 1),
  ('q005', 'Music', 'Easy', 'How many strings does a standard violin have?', array['Four', 'Five', 'Six', 'Seven'], 0),
  ('q006', 'Animals', 'Easy', 'What is the largest land animal?', array['Giraffe', 'African elephant', 'Hippopotamus', 'Rhinoceros'], 1),
  ('q007', 'Mathematics', 'Medium', 'What is the value of 7 squared plus 5 squared?', array['64', '74', '84', '94'], 1),
  ('q008', 'Technology', 'Medium', 'What does the "S" in HTTPS stand for?', array['Secure', 'Standard', 'Server', 'Static'], 0),
  ('q009', 'Literature', 'Easy', 'Who wrote "Romeo and Juliet"?', array['Charles Dickens', 'William Shakespeare', 'Jane Austen', 'Oscar Wilde'], 1),
  ('q010', 'Food', 'Easy', 'Which spice is the most expensive by weight?', array['Vanilla', 'Saffron', 'Cardamom', 'Cinnamon'], 1),
  ('q011', 'Sport', 'Medium', 'How many players are on the field per football team?', array['Nine', 'Ten', 'Eleven', 'Twelve'], 2),
  ('q012', 'World Capitals', 'Medium', 'What is the capital of Australia?', array['Sydney', 'Melbourne', 'Canberra', 'Perth'], 2),
  ('q013', 'Nature', 'Easy', 'Which gas do plants absorb for photosynthesis?', array['Oxygen', 'Carbon dioxide', 'Nitrogen', 'Hydrogen'], 1),
  ('q014', 'Movies', 'Medium', 'Which film introduced the character Ellen Ripley?', array['Blade Runner', 'Alien', 'The Thing', 'Predator'], 1),
  ('q015', 'Mythology', 'Hard', 'In Greek myth, who flew too close to the sun?', array['Icarus', 'Perseus', 'Orpheus', 'Theseus'], 0),
  ('q016', 'Geography', 'Hard', 'Which country has the most time zones?', array['Russia', 'France', 'United States', 'China'], 1),
  ('q017', 'British Culture', 'Medium', 'Which London landmark houses the Crown Jewels?', array['Buckingham Palace', 'Tower of London', 'Westminster Abbey', 'St Paul''s'], 1),
  ('q018', 'Science', 'Hard', 'What is the most abundant element in the universe?', array['Hydrogen', 'Helium', 'Oxygen', 'Carbon'], 0),
  ('q019', 'Art', 'Medium', 'Who painted the ceiling of the Sistine Chapel?', array['Raphael', 'Michelangelo', 'Leonardo da Vinci', 'Caravaggio'], 1),
  ('q020', 'Video Games', 'Medium', 'Which company created the Mario franchise?', array['Sega', 'Sony', 'Nintendo', 'Atari'], 2),
  ('q021', 'General Knowledge', 'Easy', 'How many sides does a hexagon have?', array['Five', 'Six', 'Seven', 'Eight'], 1),
  ('q022', 'History', 'Expert', 'Which treaty ended the First World War?', array['Treaty of Versailles', 'Treaty of Paris', 'Treaty of Vienna', 'Treaty of Ghent'], 0),
  ('q023', 'Popular Culture', 'Easy', 'What does "app" short for?', array['Application', 'Apparatus', 'Approach', 'Appendix'], 0),
  ('q024', 'Television', 'Medium', 'What is the standard frame rate of cinema film?', array['24 fps', '25 fps', '30 fps', '48 fps'], 0),
  ('q025', 'Space', 'Hard', 'What is the name of the galaxy nearest to the Milky Way?', array['Andromeda', 'Triangulum', 'Sombrero', 'Whirlpool'], 0),
  ('q026', 'Animals', 'Medium', 'Which mammal is the only one capable of true flight?', array['Flying squirrel', 'Bat', 'Sugar glider', 'Colugo'], 1),
  ('q027', 'Science', 'Medium', 'What is the chemical symbol for gold?', array['Go', 'Gd', 'Au', 'Ag'], 2),
  ('q028', 'Sport', 'Hard', 'How many points is a try worth in rugby union?', array['Three', 'Four', 'Five', 'Seven'], 2),
  ('q029', 'Food', 'Medium', 'Which fruit is the main ingredient of guacamole?', array['Avocado', 'Lime', 'Tomato', 'Mango'], 0),
  ('q030', 'Geography', 'Easy', 'Which ocean is the largest?', array['Atlantic', 'Indian', 'Arctic', 'Pacific'], 3)
on conflict (id) do nothing;
