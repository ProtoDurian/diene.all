/// The app-handoff carrier: `atomi-app-handoff:v1:<nonce>`.
///
/// Never log or persist the nonce.
final class AppHandoffCarrier {
  const AppHandoffCarrier._(this.nonce);

  /// The 43-character unpadded base64url nonce.
  final String nonce;

  static const String _prefix = 'atomi-app-handoff:v1:';
  static final RegExp _nonce = RegExp(r'^[A-Za-z0-9_-]{43}$');

  String get canonicalText => '$_prefix$nonce';

  /// Parses the canonical text; `null` when malformed.
  static AppHandoffCarrier? parseCanonical(String raw) {
    if (!raw.startsWith(_prefix)) {
      return null;
    }
    final String nonce = raw.substring(_prefix.length);
    if (!_nonce.hasMatch(nonce)) {
      return null;
    }
    return AppHandoffCarrier._(nonce);
  }

  /// Parses an Install Referrer string; needs exactly one `app_handoff` field.
  static AppHandoffCarrier? parseAndroidReferrer(String referrer) {
    final List<String> values = <String>[];
    for (final String pair in referrer.split('&')) {
      final int eq = pair.indexOf('=');
      if (eq < 0) {
        continue;
      }
      final String key = pair.substring(0, eq);
      if (key == 'app_handoff') {
        values.add(pair.substring(eq + 1));
      }
    }
    if (values.length != 1) {
      return null;
    }
    final String decoded;
    try {
      decoded = Uri.decodeComponent(values.single);
    } on Object {
      return null;
    }
    return parseCanonical(decoded);
  }

  /// Parses iOS clipboard text, trimming surrounding whitespace.
  static AppHandoffCarrier? parseClipboard(String clipboard) =>
      parseCanonical(clipboard.trim());
}
