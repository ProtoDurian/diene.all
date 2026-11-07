import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// Telemetry-only device info; it never affects identity.
final class DeviceInfo {
  const DeviceInfo({
    required this.platform,
    this.appVersion,
    this.osVersion,
    this.model,
  });

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

/// A redeemed Logto one-time token and the account email.
final class RedeemResult {
  const RedeemResult({
    required this.token,
    required this.email,
    this.expiresIn = 120,
  });

  final String token;
  final String email;
  final int expiresIn;
}

/// The one redeem failure (410); it reveals nothing about the account.
Problem appHandoffExpired() => const Problem(
  type: 'urn:diene:problem:app-handoff-expired',
  title: 'App handoff expired',
  status: 410,
  detail: 'This app handoff is expired or invalid.',
);

/// `POST {mount}/redeem`; every failure maps to [appHandoffExpired].
abstract interface class AppHandoffApi {
  Future<Result<RedeemResult>> redeem({
    required String nonce,
    required DeviceInfo device,
  });
}
