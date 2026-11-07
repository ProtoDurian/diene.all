import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21);

  group('SessionTokens / ResourceToken', () {
    test('validity checks and equality', () {
      // Arrange
      final SessionTokens tokens = AuthFixtures.sessionTokens(now: now);

      // Act
      // Assert
      expect(tokens.accessValidAt(now), isTrue);
      expect(
        tokens.accessValidAt(now.add(const Duration(minutes: 11))),
        isFalse,
      );
      expect(tokens.refreshValidAt(now), isTrue);
      expect(tokens, AuthFixtures.sessionTokens(now: now));

      final ResourceToken token = AuthFixtures.resourceToken(
        now: now,
        jwtToken: 'j',
      );
      expect(token.validAt(now), isTrue);
      expect(token, AuthFixtures.resourceToken(now: now, jwtToken: 'j'));
    });
  });

  group('ResourceKey', () {
    test('rejects a non-DNS label', () {
      // Arrange
      // Act
      // Assert
      expect(
        () => ResourceKey(
          platform: 'BadCase',
          landscape: 'lapras',
          service: 'api',
          resourceName: 'root',
        ),
        throwsFormatException,
      );
    });

    test('equality is by mapKey + domain', () {
      // Arrange
      // Act
      // Assert
      expect(AuthFixtures.resourceKey(), AuthFixtures.resourceKey());
    });
  });

  group('DeviceInfo / RedeemResult', () {
    test('device json omits null optionals', () {
      // Arrange
      const DeviceInfo device = DeviceInfo(platform: 'ios', appVersion: '1.2');

      // Act
      final Map<String, Object?> json = device.toJson();

      // Assert
      expect(json['platform'], 'ios');
      expect(json['appVersion'], '1.2');
      expect(json.containsKey('osVersion'), isFalse);
    });

    test('redeem result defaults expiresIn to 120', () {
      // Arrange
      // Act
      const RedeemResult result = RedeemResult(token: 't', email: 'e');

      // Assert
      expect(result.expiresIn, 120);
    });
  });

  group('BackendRegistry / RegisteredBackend', () {
    final ResourceKey key = AuthFixtures.resourceKey();

    test('rejects a duplicate backend id', () {
      // Arrange
      // Act
      // Assert
      expect(
        () => BackendRegistry(<RegisteredBackend>[
          RegisteredBackend(
            backendId: 'a',
            resources: <ResourceKey>[key],
            onboardingResource: key,
          ),
          RegisteredBackend(
            backendId: 'a',
            resources: <ResourceKey>[key],
            onboardingResource: key,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects an onboarding resource outside the resource list', () {
      // Arrange
      // Act
      // Assert
      expect(
        () => RegisteredBackend(
          backendId: 'a',
          resources: <ResourceKey>[key],
          onboardingResource: AuthFixtures.resourceKey(service: 'other'),
        ),
        throwsArgumentError,
      );
    });

    test('resourceUnion dedups across backends', () {
      // Arrange
      final ResourceKey keyB = AuthFixtures.resourceKey(service: 'billing');

      // Act
      final BackendRegistry registry = BackendRegistry(<RegisteredBackend>[
        RegisteredBackend(
          backendId: 'a',
          resources: <ResourceKey>[key],
          onboardingResource: key,
        ),
        RegisteredBackend(
          backendId: 'b',
          resources: <ResourceKey>[key, keyB],
          onboardingResource: keyB,
        ),
      ]);

      // Assert
      expect(registry.resourceUnion.length, 2);
      expect(registry.byId('a')?.backendId, 'a');
    });
  });
}
