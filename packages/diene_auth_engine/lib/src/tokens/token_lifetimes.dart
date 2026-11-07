/// Fixed token lifetimes; these are rules, not config knobs.
abstract final class TokenLifetimes {
  /// Access tokens live 10 minutes.
  static const Duration access = Duration(minutes: 10);

  /// Refresh tokens live 14 days.
  static const Duration refresh = Duration(days: 14);

  /// Refresh tokens rotate on every use; a reused one is theft.
  static const bool refreshRotating = true;

  /// The app re-mints the access token on open.
  static const bool remintOnOpen = true;
}
