# GIGSFLIX

## Secure administrator access and visitor analytics

1. Run the complete `supabase_setup.sql` script in the Supabase Dashboard SQL Editor. It enables anonymous, session-only usage events, locks movie and storage changes to authorized administrators, and enables live analytics updates.
2. In Supabase Dashboard, open **Authentication → Users** and create the administrator account you want to use on the site.
3. Add that user's email to the administrator allowlist in the SQL Editor:

   ```sql
   insert into public.gigsflix_admin_users (user_id)
   select id
   from auth.users
   where lower(email) = lower('YOUR_ADMIN_EMAIL')
   on conflict do nothing;
   ```

4. Open **Administrator Access** on the site and sign in with that Supabase Auth email and password.

The analytics dashboard shows anonymous per-tab sessions, recent activity, and full-movie playback starts (previews are not counted). A session identifier is kept in `sessionStorage`; analytics records do not store names or IP addresses. Active visitors are sessions with activity in the last two minutes. Event history remains in Supabase until you remove it; to delete events older than 90 days, run:

```sql
delete from public.visitor_analytics_events
where created_at < now() - interval '90 days';
```