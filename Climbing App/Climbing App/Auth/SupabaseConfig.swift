import Foundation

/// Where Trace's accounts live.
///
/// Two values, in source, because both are meant to be public. The URL is a
/// hostname and the anon key is the publishable key: Supabase issues it to be
/// shipped inside client apps, it identifies the project rather than granting
/// anything, and every permission it carries is whatever row-level security
/// says an anonymous caller may do. On this project that is nothing, because
/// Trace stores no data on the server. The only thing the key can reach is
/// Auth, which is the point of it.
///
/// The key that must never be here is the service role key. It bypasses every
/// policy, anyone can pull it out of a shipped binary, and it is why deleting
/// an account goes through the security-definer function in `Supabase.sql`
/// rather than through Supabase's own admin endpoint.
///
/// Empty values mean accounts are switched off, and the app runs in local-only
/// mode: `LocalStartScreen` asks for a name and everything stays on the phone.
/// That is a supported state, not a broken one.
enum SupabaseConfig {
    /// The project's API URL, from Settings, Data API.
    static let url = "https://uksqwnfmqytwftpttbdk.supabase.co"

    /// The anon, or publishable, key from the same page.
    static let anonKey = ""
}
