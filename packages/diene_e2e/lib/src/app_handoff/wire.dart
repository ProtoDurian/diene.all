/// App-handoff (deferred-login) JSON/HTTP v1 wire models.
library;

/// Default mount base path. The mint route is `POST {mount}` and the redeem
/// route is `POST {mount}/redeem`.
const String appHandoffDefaultMount = '/app-handoff';

/// The redeem sub-path appended to the configured mount.
const String appHandoffRedeemPath = 'redeem';

/// Successful mint response body: `{ "nonce", "expiresAt" }`.
///
/// [expiresAt] is an RFC 3339 UTC instant, kept verbatim.
class AppHandoffMint {
  const AppHandoffMint({required this.nonce, required this.expiresAt});

  factory AppHandoffMint.fromJson(Map<String, Object?> json) => AppHandoffMint(
    nonce: json['nonce']! as String,
    expiresAt: json['expiresAt']! as String,
  );

  final String nonce;
  final String expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'nonce': nonce,
    'expiresAt': expiresAt,
  };
}

/// Telemetry-only device descriptor on a redeem request; it must not affect
/// identity or authorization.
class AppHandoffDevice {
  const AppHandoffDevice({
    required this.platform,
    this.appVersion,
    this.osVersion,
    this.model,
  });

  factory AppHandoffDevice.fromJson(Map<String, Object?> json) =>
      AppHandoffDevice(
        platform: json['platform']! as String,
        appVersion: json['appVersion'] as String?,
        osVersion: json['osVersion'] as String?,
        model: json['model'] as String?,
      );

  /// `android` or `ios`.
  final String platform;
  final String? appVersion;
  final String? osVersion;
  final String? model;

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    if (appVersion != null) 'appVersion': appVersion,
    if (osVersion != null) 'osVersion': osVersion,
    if (model != null) 'model': model,
  };
}

/// Redeem request body `{ "nonce", "device" }`.
class AppHandoffRedeemRequest {
  const AppHandoffRedeemRequest({required this.nonce, required this.device});

  factory AppHandoffRedeemRequest.fromJson(Map<String, Object?> json) =>
      AppHandoffRedeemRequest(
        nonce: json['nonce']! as String,
        device: AppHandoffDevice.fromJson(
          json['device']! as Map<String, Object?>,
        ),
      );

  final String nonce;
  final AppHandoffDevice device;

  Map<String, Object?> toJson() => <String, Object?>{
    'nonce': nonce,
    'device': device.toJson(),
  };
}

/// Successful redeem response `{ "token", "email", "expiresIn" }`.
class AppHandoffRedeemResponse {
  const AppHandoffRedeemResponse({
    required this.token,
    required this.email,
    this.expiresIn = appHandoffTokenExpiresInSeconds,
  });

  factory AppHandoffRedeemResponse.fromJson(Map<String, Object?> json) =>
      AppHandoffRedeemResponse(
        token: json['token']! as String,
        email: json['email']! as String,
        expiresIn: json['expiresIn'] as int? ?? appHandoffTokenExpiresInSeconds,
      );

  final String token;
  final String email;
  final int expiresIn;

  Map<String, Object?> toJson() => <String, Object?>{
    'token': token,
    'email': email,
    'expiresIn': expiresIn,
  };
}

/// Fixed one-time-token lifetime for a redeemed handoff, in seconds.
const int appHandoffTokenExpiresInSeconds = 120;

/// The single redeem failure: problem id `AppHandoffExpired`, status `410`.
/// Every redeem failure returns exactly this body, so it reveals nothing about
/// the account.
class AppHandoffExpired {
  const AppHandoffExpired({required this.type});

  /// [typeUri] is the owning service's problem type URI for this id.
  factory AppHandoffExpired.withType(String typeUri) =>
      AppHandoffExpired(type: typeUri);

  static const String problemId = 'AppHandoffExpired';
  static const int status = 410;
  static const String title = 'App handoff expired';
  static const String detail = 'This app handoff is expired or invalid.';

  /// The problem `type` URI.
  final String type;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'title': title,
    'status': status,
    'detail': detail,
    'data': const <String, Object?>{},
  };
}
