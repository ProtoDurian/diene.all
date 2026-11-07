import 'package:flutter/services.dart';

import '../deferred/deferred_login.dart';

/// Reads the iOS clipboard; clears it only if it still holds the carrier.
final class ClipboardCarrierReader implements ClipboardCarrierSource {
  const ClipboardCarrierReader();

  @override
  Future<String?> read() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  Future<void> clearIfEquals(String value) async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text?.trim() == value) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}

/// An Install Referrer source from callbacks; the plugin stays in the app.
final class CallbackInstallReferrerSource implements InstallReferrerSource {
  const CallbackInstallReferrerSource({
    required this._readReferrer,
    required this._markProcessed,
  });

  final Future<String?> Function() _readReferrer;
  final Future<void> Function() _markProcessed;

  @override
  Future<String?> read() => _readReferrer();

  @override
  Future<void> markProcessed() => _markProcessed();
}
