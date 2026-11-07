import '../tokens/resource_key.dart';
import '../tokens/session_tokens.dart';

/// The identity-provider seam; Logto is its only implementation.
///
/// Any method may throw; callers wrap errors into a `Result`.
abstract interface class AuthProvider {
  /// Runs the interactive sign-in; [extraParams] carry the app-handoff token.
  Future<SessionTokens> signIn({Map<String, String> extraParams});

  /// Exchanges a rotating refresh token for a fresh pair.
  Future<SessionTokens> refresh(SessionTokens current);

  /// Silently re-mints the access token on app open, keeping the refresh token.
  Future<SessionTokens> reMintOnOpen(SessionTokens current);

  /// Clears the provider-side session.
  Future<void> signOut();

  /// Acquires a fresh access token for one resource.
  Future<ResourceToken> resourceToken(ResourceKey key);

  /// The raw ID token of the active session, if any.
  Future<String?> idToken();

  /// A claim-bearing token fetched fresh from the server, never from cache.
  ///
  /// Returns `null` when freshness cannot be guaranteed, so callers fail closed.
  Future<String?> freshClaimToken();
}
