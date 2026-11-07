/// App-handoff (deferred-login) carrier codec.
library;

import 'package:diene_auth_engine/diene_auth_engine.dart'
    show AppHandoffCarrier;

/// Scheme prefix of the canonical carrier text.
const String appHandoffCarrierScheme = 'atomi-app-handoff';

/// Carrier wire version.
const String appHandoffCarrierVersion = 'v1';

/// The Android Play Install Referrer field name that carries the nonce.
const String appHandoffReferrerField = 'app_handoff';

/// Number of ASCII characters in a valid nonce: 32 random bytes encoded as
/// RFC 4648 base64url without padding.
const int appHandoffNonceLength = 43;

const String _prefix = '$appHandoffCarrierScheme:$appHandoffCarrierVersion:';

/// Whether [nonce] is syntactically a valid nonce: exactly
/// [appHandoffNonceLength] characters from the unpadded base64url alphabet.
bool isValidAppHandoffNonce(String nonce) =>
    AppHandoffCarrier.parseCanonical('$_prefix$nonce') != null;

/// Builds the canonical carrier text `atomi-app-handoff:v1:<nonce>`.
///
/// Throws [ArgumentError] if [nonce] is not a valid nonce.
String buildAppHandoffCarrier(String nonce) {
  final AppHandoffCarrier? carrier = AppHandoffCarrier.parseCanonical(
    '$_prefix$nonce',
  );
  if (carrier == null) {
    throw ArgumentError.value(
      nonce,
      'nonce',
      'not a valid C0 app-handoff nonce',
    );
  }
  return carrier.canonicalText;
}

/// Parses the canonical carrier text and returns the nonce, or `null` when the
/// text is absent or does not match `atomi-app-handoff:v1:<valid-nonce>`.
String? parseAppHandoffCarrier(String? carrier) =>
    carrier == null ? null : AppHandoffCarrier.parseCanonical(carrier)?.nonce;

/// Builds an Android Play Install Referrer string carrying [nonce] as one
/// `application/x-www-form-urlencoded` field `app_handoff=<percent-encoded
/// canonical carrier>`.
///
/// [extraFields] (campaign parameters such as `utm_source`) follow the
/// `app_handoff` field.
String buildAppHandoffInstallReferrer(
  String nonce, {
  Map<String, String> extraFields = const <String, String>{},
}) {
  final String carrier = buildAppHandoffCarrier(nonce);
  final List<String> pairs = <String>[
    '$appHandoffReferrerField=${Uri.encodeQueryComponent(carrier)}',
    for (final MapEntry<String, String> entry in extraFields.entries)
      '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
  ];
  return pairs.join('&');
}

/// Extracts the nonce from an Android Play Install Referrer [referrer], or
/// `null` when it is absent or invalid.
///
/// Zero or duplicate `app_handoff` fields count as absent; other campaign
/// fields are ignored.
String? parseAppHandoffInstallReferrer(String? referrer) {
  if (referrer == null || referrer.isEmpty) return null;
  final List<String?> values = <String?>[];
  for (final String pair in referrer.split('&')) {
    if (pair.isEmpty) continue;
    final int eq = pair.indexOf('=');
    final String key = eq < 0 ? pair : pair.substring(0, eq);
    if (_decodeQueryComponent(key) != appHandoffReferrerField) continue;
    values.add(_decodeQueryComponent(eq < 0 ? '' : pair.substring(eq + 1)));
  }
  if (values.length != 1) return null;
  return parseAppHandoffCarrier(values.single);
}

/// Extracts the nonce from iOS clipboard [contents], or `null` when absent or
/// invalid. Leading and trailing ASCII whitespace is trimmed first.
String? parseAppHandoffClipboard(String? contents) =>
    parseAppHandoffCarrier(_trimAscii(contents));

String? _decodeQueryComponent(String component) {
  try {
    return Uri.decodeQueryComponent(component);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

String? _trimAscii(String? value) {
  if (value == null) return null;
  int start = 0;
  int end = value.length;
  bool isAsciiWs(int c) => c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d;
  while (start < end && isAsciiWs(value.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isAsciiWs(value.codeUnitAt(end - 1))) {
    end--;
  }
  return value.substring(start, end);
}
