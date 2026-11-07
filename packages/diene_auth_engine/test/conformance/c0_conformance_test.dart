import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _fixturesPath = 'test/fixtures/c0';

Object? _sortKeys(Object? value) {
  if (value is Map<Object?, Object?>) {
    final List<String> keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sortKeys(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_sortKeys).toList();
  }
  return value;
}

String _canonical(Object? value) => jsonEncode(_sortKeys(value));

Future<void> _checkConfigSchema(Object? fixture) async {
  expect(_canonical(AuthEngineConfig.blockSchema), _canonical(fixture));
}

Future<void> _checkRedeemMounts(Object? fixture) async {
  for (final Object? raw in fixture! as List<Object?>) {
    final Map<String, Object?> sample = (raw! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final AuthEngineConfig config =
        AuthEngineConfig.fromBlock(<String, Object?>{
          'issuer': 'https://issuer.example.test/oidc',
          'endpoint': 'https://issuer.example.test',
          'appId': 'app',
          'redirectUri': 'io.atomi.app://callback',
          'appHandoffMount': ?sample['mount'],
        });
    final List<Uri> sent = <Uri>[];
    final HttpAppHandoffApi api = HttpAppHandoffApi(
      base: Uri.parse(sample['base']! as String),
      redeemPath: config.redeemPath,
      client: MockClient((http.Request request) async {
        sent.add(request.url);
        return http.Response('{}', 410);
      }),
    );
    await api.redeem(
      nonce: 'A' * 43,
      device: const DeviceInfo(platform: 'android'),
    );
    expect(sent.single.toString(), sample['redeemUrl'], reason: '$sample');
  }
}

const Map<String, Future<void> Function(Object?)> _checks =
    <String, Future<void> Function(Object?)>{
      'config_block_schema.json': _checkConfigSchema,
      'redeem_mounts.json': _checkRedeemMounts,
    };

void main() {
  final Map<String, Object?> manifest =
      (jsonDecode(File('$_fixturesPath/manifest.json').readAsStringSync())!
              as Map<Object?, Object?>)
          .cast<String, Object?>();
  final Map<String, Object?> fixtures =
      (manifest['fixtures']! as Map<Object?, Object?>).cast<String, Object?>();

  test('the manifest is local and pins every checked fixture', () {
    // Arrange
    final Set<String> checked = _checks.keys.toSet();

    // Act
    final Set<String> pinned = fixtures.keys.toSet();

    // Assert
    expect(manifest['authority'], 'local-regression-only');
    expect(manifest['algorithm'], 'sha256');
    expect(pinned, checked);
  });

  group('local fixtures', () {
    fixtures.forEach((String name, Object? rawDigest) {
      test(name, () async {
        // Arrange
        final List<int> bytes = File('$_fixturesPath/$name').readAsBytesSync();

        // Act
        final String digest = sha256.convert(bytes).toString();

        // Assert
        expect(
          digest,
          rawDigest,
          reason: 'fixture "$name" digest drifted from the manifest',
        );
        await _checks[name]!(jsonDecode(utf8.decode(bytes)));
      });
    });
  });
}
