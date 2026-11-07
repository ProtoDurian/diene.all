import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/handoff_harness.dart';

const String _fixturesPath = 'test/fixtures/c0';
const String _valid = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Map<String, Object?> _object(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();

List<String> _strings(Object? value) =>
    (value! as List<Object?>).cast<String>();

Map<String, List<String>> _helperExports() {
  final String source = File('lib/test_helper.dart').readAsStringSync();
  final RegExp export = RegExp(
    r"export 'package:(\w+)/test_helper\.dart'(?:\s+hide ([^;]+))?;",
  );
  return <String, List<String>>{
    for (final RegExpMatch m in export.allMatches(source))
      m[1]!: m[2] == null
          ? <String>[]
          : m[2]!.split(',').map((String s) => s.trim()).toList(),
  };
}

List<String> _runtimeExports() {
  final String source = File('lib/diene_e2e.dart').readAsStringSync();
  return RegExp(r"export 'package:(\w+)/(\w+)\.dart';")
      .allMatches(source)
      .where((RegExpMatch m) => m[1] == m[2])
      .map((RegExpMatch m) => m[1]!)
      .toList();
}

Map<String, Uri> _packageLibs() {
  final File config = File('../../.dart_tool/package_config.json');
  final List<Map<String, Object?>> packages =
      (_object(jsonDecode(config.readAsStringSync()))['packages']!
              as List<Object?>)
          .map(_object)
          .toList();
  Uri lib(Map<String, Object?> p) {
    final Uri root = config.absolute.uri.resolve(p['rootUri']! as String);
    final Uri dir = root.path.endsWith('/')
        ? root
        : root.replace(path: '${root.path}/');
    return dir.resolve(p['packageUri']! as String);
  }

  return <String, Uri>{
    for (final Map<String, Object?> p in packages) p['name']! as String: lib(p),
  };
}

Future<void> _checkHelperBundle(Object? fixture) async {
  final Map<String, Object?> bundle = _object(fixture);
  expect(_runtimeExports(), _strings(bundle['runtime']));
  expect(_helperExports(), <String, List<String>>{
    for (final MapEntry<String, Object?> e in _object(
      bundle['passthroughs'],
    ).entries)
      e.key: _strings(e.value),
  });
  final Map<String, Uri> libs = _packageLibs();
  for (final String member in _strings(bundle['runtime'])) {
    expect(
      File.fromUri(libs[member]!.resolve('$member.dart')).existsSync(),
      isTrue,
      reason: member,
    );
  }
  for (final String member in _strings(bundle['withoutHelper'])) {
    expect(
      File.fromUri(libs[member]!.resolve('test_helper.dart')).existsSync(),
      isFalse,
      reason: member,
    );
  }
  for (final String member in _strings(bundle['notInDart'])) {
    expect(libs.containsKey(member), isFalse, reason: member);
  }
}

Future<void> _checkRedeemFailures(Object? fixture) async {
  final List<String> bodies = <String>[];
  for (final Object? raw in fixture! as List<Object?>) {
    final Map<String, Object?> row = _object(raw);
    final String name = row['name']! as String;
    final HandoffHarness h = await HandoffHarness.start();
    try {
      final String nonce = await h.mint();
      final HttpReply reply = await _fail(h, row['case']! as String, nonce);
      expect(reply.status, 410, reason: name);
      expect(decodeObject(reply.body), h.stub.expiredBody, reason: name);
      expect(reply.headers['cache-control'], 'no-store', reason: name);
      expect(reply.headers['content-type'], 'application/json', reason: name);
      bodies.add(reply.body);
    } finally {
      await h.close();
    }
  }
  expect(bodies.toSet(), hasLength(1));
}

Future<HttpReply> _withBody(
  HandoffHarness h,
  String nonce,
  Map<String, Object?> body,
) async {
  final HttpReply reply = await h.redeem(jsonEncode(body));
  expect((await h.redeemNonce(nonce)).status, 200, reason: 'not consumed');
  return reply;
}

Future<HttpReply> _fail(HandoffHarness h, String kind, String nonce) async {
  Map<String, Object?> device([Map<String, Object?> extra = const {}]) =>
      <String, Object?>{'platform': 'android', ...extra};
  switch (kind) {
    case 'unknown':
      return h.redeemNonce(_valid);
    case 'expired':
      h.now = h.now.add(AppHandoffStub.nonceTtl);
      return h.redeemNonce(nonce);
    case 'replayed':
      await h.redeemNonce(nonce);
      return h.redeemNonce(nonce);
    case 'deleted':
      h.stub.addUser(
        const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com', deleted: true),
      );
      return h.redeemNonce(nonce);
    case 'suspended':
      h.stub.addUser(
        const AppHandoffUser(
          sub: 'u1',
          primaryEmail: 'a@b.com',
          isSuspended: true,
        ),
      );
      return h.redeemNonce(nonce);
    case 'rebound':
      h.stub.addUser(const AppHandoffUser(sub: 'u1', primaryEmail: 'c@d.com'));
      return h.redeemNonce(nonce);
    case 'noEmail':
      h.stub.addUser(const AppHandoffUser(sub: 'u1', primaryEmail: null));
      return h.redeemNonce(nonce);
    case 'notJson':
      return h.redeem('{');
    case 'notObject':
      return h.redeem('[1]');
    case 'empty':
      return h.redeem('');
    case 'extraKey':
      return _withBody(h, nonce, <String, Object?>{
        'nonce': nonce,
        'device': device(),
        'extra': 1,
      });
    case 'extraDeviceKey':
      return _withBody(h, nonce, <String, Object?>{
        'nonce': nonce,
        'device': device(<String, Object?>{'serial': 'x'}),
      });
    case 'noDevice':
      return _withBody(h, nonce, <String, Object?>{'nonce': nonce});
    case 'deviceNotObject':
      return _withBody(h, nonce, <String, Object?>{
        'nonce': nonce,
        'device': 'android',
      });
    case 'noPlatform':
      return _withBody(h, nonce, <String, Object?>{
        'nonce': nonce,
        'device': <String, Object?>{'model': 'Pixel 9'},
      });
    case 'badPlatform':
      return _withBody(h, nonce, <String, Object?>{
        'nonce': nonce,
        'device': <String, Object?>{'platform': 'web'},
      });
    case 'nonceNotString':
      return _withBody(h, nonce, <String, Object?>{
        'nonce': 7,
        'device': device(),
      });
    case 'badOptional':
      return _withBody(h, nonce, <String, Object?>{
        'nonce': nonce,
        'device': device(<String, Object?>{'appVersion': 1}),
      });
  }
  fail('unknown failure case $kind');
}

const Map<String, Future<void> Function(Object?)> _checks =
    <String, Future<void> Function(Object?)>{
      'helper_bundle.json': _checkHelperBundle,
      'redeem_failures.json': _checkRedeemFailures,
    };

void main() {
  final Map<String, Object?> manifest = _object(
    jsonDecode(File('$_fixturesPath/manifest.json').readAsStringSync()),
  );
  final Map<String, Object?> fixtures = _object(manifest['fixtures']);

  test('the manifest is local and pins every checked fixture', () {
    // Arrange
    final Set<String> checked = _checks.keys.toSet();

    // Act
    final Set<String> pinned = fixtures.keys.toSet();
    final Set<String> present = Directory(_fixturesPath)
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where((String name) => name != 'manifest.json')
        .toSet();

    // Assert
    expect(manifest['authority'], 'local-regression-only');
    expect(manifest['algorithm'], 'sha256');
    expect(pinned, checked);
    expect(present, pinned);
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
