-- Run in Supabase Dashboard > SQL Editor to install or update the app schema and policies.

create table if not exists public.movies (
    id text primary key,
    title text not null,
    description text not null default '',
    genre text not null,
    allow_ratings boolean not null default true,
    poster_url text,
    video_url text,
    poster_path text,
    video_path text,
    created_at timestamptz not null default now()
);

create table if not exists public.movie_ratings (
    movie_id text not null references public.movies(id) on delete cascade,
    voter_id text not null,
    rating smallint not null check (rating between 1 and 5),
    created_at timestamptz not null default now(),
    primary key (movie_id, voter_id)
);

create table if not exists public.gigsflix_admin_users (
    user_id uuid primary key references auth.users(id) on delete cascade
);

create table if not exists public.visitor_analytics_events (
    id uuid primary key default gen_random_uuid(),
    visitor_id uuid not null,
    event_type text not null check (event_type in ('session_start', 'heartbeat', 'movie_play')),
    movie_id text,
    movie_title text,
    created_at timestamptz not null default now(),
    constraint visitor_analytics_movie_fields check (
        (event_type = 'movie_play' and movie_id is not null and movie_title is not null and length(trim(movie_title)) between 1 and 200)
        or (event_type <> 'movie_play' and movie_id is null and movie_title is null)
    )
);

create index if not exists visitor_analytics_created_at_idx
    on public.visitor_analytics_events (created_at desc);
create index if not exists visitor_analytics_visitor_created_at_idx
    on public.visitor_analytics_events (visitor_id, created_at desc);

create or replace function public.is_gigsflix_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.gigsflix_admin_users
        where user_id = auth.uid()
    );
$$;

revoke all on function public.is_gigsflix_admin() from public, anon;
grant execute on function public.is_gigsflix_admin() to authenticated;

alter table public.movies enable row level security;
alter table public.movie_ratings enable row level security;
alter table public.gigsflix_admin_users enable row level security;
alter table public.visitor_analytics_events enable row level security;
grant usage on schema public to anon, authenticated;
grant select on table public.movies to anon, authenticated;
revoke insert, update, delete on table public.movies from anon, authenticated;
grant insert, update, delete on table public.movies to authenticated;
grant select, insert, update on table public.movie_ratings to anon, authenticated;
revoke all on table public.gigsflix_admin_users from public, anon, authenticated;
revoke all on table public.visitor_analytics_events from public, anon, authenticated;
grant insert on table public.visitor_analytics_events to anon, authenticated;
grant select on table public.visitor_analytics_events to authenticated;

drop policy if exists "Public can read movies" on public.movies;
create policy "Public can read movies"
on public.movies for select
using (true);

drop policy if exists "Public can add movies" on public.movies;
drop policy if exists "Admins can add movies" on public.movies;
create policy "Admins can add movies"
on public.movies for insert
to authenticated
with check (public.is_gigsflix_admin());

drop policy if exists "Public can delete movies" on public.movies;
drop policy if exists "Admins can delete movies" on public.movies;
create policy "Admins can delete movies"
on public.movies for delete
to authenticated
using (public.is_gigsflix_admin());

drop policy if exists "Admins can update movies" on public.movies;
create policy "Admins can update movies"
on public.movies for update
to authenticated
using (public.is_gigsflix_admin())
with check (public.is_gigsflix_admin());

drop policy if exists "Public can read movie ratings" on public.movie_ratings;
create policy "Public can read movie ratings"
on public.movie_ratings for select
using (true);

drop policy if exists "Public can add movie ratings" on public.movie_ratings;
create policy "Public can add movie ratings"
on public.movie_ratings for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can update movie ratings" on public.movie_ratings;
create policy "Public can update movie ratings"
on public.movie_ratings for update
to anon, authenticated
using (true)
with check (true);

drop policy if exists "Visitors can record anonymous activity" on public.visitor_analytics_events;
create policy "Visitors can record anonymous activity"
on public.visitor_analytics_events for insert
to anon, authenticated
with check (
    created_at >= now() - interval '5 minutes'
    and created_at <= now() + interval '1 minute'
    and (
        event_type in ('session_start', 'heartbeat')
        or (
            event_type = 'movie_play'
            and exists (
                select 1
                from public.movies
                where id = visitor_analytics_events.movie_id
            )
        )
    )
);

drop policy if exists "Admins can read visitor analytics" on public.visitor_analytics_events;
create policy "Admins can read visitor analytics"
on public.visitor_analytics_events for select
to authenticated
using (public.is_gigsflix_admin());

create or replace function public.get_gigsflix_analytics()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    analytics jsonb;
begin
    if not public.is_gigsflix_admin() then
        raise exception 'Administrator access required';
    end if;

    select jsonb_build_object(
        'totalVisitors', summary.total_visitors,
        'visitorsLast30Days', summary.visitors_last_30_days,
        'activeVisitors', summary.active_visitors,
        'totalPlays', summary.total_plays,
        'topMovies', coalesce((
            select jsonb_agg(
                jsonb_build_object('title', popular.movie_title, 'plays', popular.plays)
                order by popular.plays desc, popular.movie_title
            )
            from (
                select movie_title, count(*) as plays
                from public.visitor_analytics_events
                where event_type = 'movie_play'
                group by movie_title
                order by count(*) desc, movie_title
                limit 10
            ) as popular
        ), '[]'::jsonb),
        'recentVisitors', coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'visitorId', recent.visitor_id,
                    'firstSeen', recent.first_seen,
                    'lastSeen', recent.last_seen,
                    'plays', recent.plays,
                    'movies', recent.movies
                )
                order by recent.last_seen desc
            )
            from (
                select
                    visitor_id,
                    min(created_at) as first_seen,
                    max(created_at) as last_seen,
                    count(*) filter (where event_type = 'movie_play') as plays,
                    coalesce(
                        jsonb_agg(
                            jsonb_build_object('title', movie_title, 'watchedAt', created_at)
                            order by created_at desc
                        ) filter (where event_type = 'movie_play'),
                        '[]'::jsonb
                    ) as movies
                from public.visitor_analytics_events
                group by visitor_id
                order by max(created_at) desc
                limit 25
            ) as recent
        ), '[]'::jsonb)
    )
    into analytics
    from (
        select
            count(distinct visitor_id) as total_visitors,
            count(distinct visitor_id) filter (
                where created_at >= now() - interval '30 days'
            ) as visitors_last_30_days,
            count(distinct visitor_id) filter (
                where created_at >= now() - interval '2 minutes'
                    and event_type in ('session_start', 'heartbeat', 'movie_play')
            ) as active_visitors,
            count(*) filter (where event_type = 'movie_play') as total_plays
        from public.visitor_analytics_events
    ) as summary;

    return analytics;
end;
$$;

revoke all on function public.get_gigsflix_analytics() from public, anon;
grant execute on function public.get_gigsflix_analytics() to authenticated;

insert into storage.buckets (id, name, public)
values ('gigsflix-media', 'gigsflix-media', true)
on conflict (id) do update set public = true;

drop policy if exists "Public can read GIGSFLIX media" on storage.objects;
create policy "Public can read GIGSFLIX media"
on storage.objects for select
using (bucket_id = 'gigsflix-media');

drop policy if exists "Public can upload GIGSFLIX media" on storage.objects;
drop policy if exists "Admins can upload GIGSFLIX media" on storage.objects;
create policy "Admins can upload GIGSFLIX media"
on storage.objects for insert
to authenticated
with check (bucket_id = 'gigsflix-media' and public.is_gigsflix_admin());

drop policy if exists "Public can delete GIGSFLIX media" on storage.objects;
drop policy if exists "Admins can update GIGSFLIX media" on storage.objects;
create policy "Admins can update GIGSFLIX media"
on storage.objects for update
to authenticated
using (bucket_id = 'gigsflix-media' and public.is_gigsflix_admin())
with check (bucket_id = 'gigsflix-media' and public.is_gigsflix_admin());

drop policy if exists "Admins can delete GIGSFLIX media" on storage.objects;
create policy "Admins can delete GIGSFLIX media"
on storage.objects for delete
to authenticated
using (bucket_id = 'gigsflix-media' and public.is_gigsflix_admin());

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'visitor_analytics_events'
    ) then
        alter publication supabase_realtime add table public.visitor_analytics_events;
    end if;
end;
$$;
