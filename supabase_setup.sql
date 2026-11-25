-- Run this once in Supabase Dashboard > SQL Editor.

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

alter table public.movies enable row level security;
alter table public.movie_ratings enable row level security;
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on table public.movies to anon, authenticated;
grant select, insert, update on table public.movie_ratings to anon, authenticated;

drop policy if exists "Public can read movies" on public.movies;
create policy "Public can read movies"
on public.movies for select
using (true);

drop policy if exists "Public can add movies" on public.movies;
create policy "Public can add movies"
on public.movies for insert
to anon, authenticated
with check (true);

drop policy if exists "Public can delete movies" on public.movies;
create policy "Public can delete movies"
on public.movies for delete
to anon, authenticated
using (true);

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

insert into storage.buckets (id, name, public)
values ('gigsflix-media', 'gigsflix-media', true)
on conflict (id) do update set public = true;

drop policy if exists "Public can read GIGSFLIX media" on storage.objects;
create policy "Public can read GIGSFLIX media"
on storage.objects for select
using (bucket_id = 'gigsflix-media');

drop policy if exists "Public can upload GIGSFLIX media" on storage.objects;
create policy "Public can upload GIGSFLIX media"
on storage.objects for insert
to anon, authenticated
with check (bucket_id = 'gigsflix-media');

drop policy if exists "Public can delete GIGSFLIX media" on storage.objects;
create policy "Public can delete GIGSFLIX media"
on storage.objects for delete
to anon, authenticated
using (bucket_id = 'gigsflix-media');
