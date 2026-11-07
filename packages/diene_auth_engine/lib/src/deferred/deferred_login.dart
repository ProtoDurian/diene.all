import 'package:diene_problems/diene_problems.dart';
import 'carrier.dart';
import 'redeem_client.dart';

/// Reads the Android Install Referrer.
abstract interface class InstallReferrerSource {
  Future<String?> read();

  /// Marks the referrer processed so it is never redeemed twice.
  Future<void> markProcessed();
}

/// Reads the iOS clipboard carrier.
abstract interface class ClipboardCarrierSource {
  Future<String?> read();

  /// Clears the clipboard only if it still equals [value].
  Future<void> clearIfEquals(String value);
}

sealed class DeferredLoginOutcome {
  const DeferredLoginOutcome();
}

/// A carrier was redeemed; pass [extraParams] to `signIn(extraParams:)`.
final class DeferredLoginReady extends DeferredLoginOutcome {
  const DeferredLoginReady(this.extraParams);

  final Map<String, String> extraParams;
}

/// Fall back to interactive login; [problem] is set on a redeem failure.
final class DeferredLoginFallback extends DeferredLoginOutcome {
  const DeferredLoginFallback([this.problem]);

  final Problem? problem;
}

/// Reads a carrier, marks it used, then calls `POST {mount}/redeem`.
///
/// Any failure falls back to interactive login; there is no retry loop.
final class DeferredLoginClient {
  const DeferredLoginClient({
    required this._api,
    required this._device,
    this._referrer,
    this._clipboard,
  });

  final AppHandoffApi _api;
  final DeviceInfo _device;
  final InstallReferrerSource? _referrer;
  final ClipboardCarrierSource? _clipboard;

  /// Never throws.
  Future<DeferredLoginOutcome> prepare() async {
    final InstallReferrerSource? referrer = _referrer;
    if (referrer != null) {
      final String? raw = await _safeRead(referrer.read);
      final AppHandoffCarrier? carrier = raw == null
          ? null
          : AppHandoffCarrier.parseAndroidReferrer(raw);
      if (carrier != null) {
        await _safe(referrer.markProcessed);
        return _redeem(carrier);
      }
    }

    final ClipboardCarrierSource? clipboard = _clipboard;
    if (clipboard != null) {
      final String? raw = await _safeRead(clipboard.read);
      if (raw != null) {
        final AppHandoffCarrier? carrier = AppHandoffCarrier.parseClipboard(
          raw,
        );
        if (carrier != null) {
          await _safe(() => clipboard.clearIfEquals(raw.trim()));
          return _redeem(carrier);
        }
      }
    }

    return const DeferredLoginFallback();
  }

  Future<DeferredLoginOutcome> _redeem(AppHandoffCarrier carrier) async {
    final result = await _api.redeem(nonce: carrier.nonce, device: _device);
    return result.match(
      ok: (RedeemResult redeemed) => DeferredLoginReady(<String, String>{
        'one_time_token': redeemed.token,
        'login_hint': redeemed.email,
      }),
      err: DeferredLoginFallback.new,
    );
  }

  static Future<String?> _safeRead(Future<String?> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }

  static Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Best effort; never block login.
    }
  }
}
