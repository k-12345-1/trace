-- What Trace needs on a Supabase project, and nothing else.
--
-- Trace stores no climbing data on a server. There are no tables here, no
-- policies, and no storage buckets, because nothing about a climb ever leaves
-- the phone. The only thing the project does is answer "is this person who they
-- say they are", which Supabase Auth does on its own.
--
-- This one function exists because Apple requires that an account made in an
-- app can be destroyed in that app, and Supabase's own delete-user endpoint
-- takes a service role key. A service role key in a shipped binary is a key
-- anybody can extract and then use to delete anybody, so instead the account
-- deletes itself: the function runs as its owner, and `auth.uid()` makes it
-- physically unable to delete anyone but the caller.
--
-- Run this once, in the SQL editor, against the project whose URL and anon key
-- are set as SUPABASE_URL and SUPABASE_ANON_KEY in the app's build settings.

create or replace function public.delete_current_user()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

-- Callable by a signed-in climber and by nobody else. `anon` is not granted it:
-- an unauthenticated caller has no uid, so it could only ever fail, and leaving
-- it ungranted means the endpoint does not exist for them at all.
revoke all on function public.delete_current_user() from public, anon;
grant execute on function public.delete_current_user() to authenticated;
