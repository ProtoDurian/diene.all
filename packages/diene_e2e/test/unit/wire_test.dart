import 'package:diene_e2e/diene_e2e.dart';
import 'package:flutter_test/flutter_test.dart';

const String _nonce = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

void main() {
  test('the routes are POST {mount} and POST {mount}/redeem', () {
    // Arrange
    const String mount = appHandoffDefaultMount;

    // Act
    const String redeem = '$mount/$appHandoffRedeemPath';

    // Assert
    expect(mount, '/app-handoff');
    expect(redeem, '/app-handoff/redeem');
  });

  test(
    'AppHandoffMint round-trips through JSON, keeping expiresAt as sent',
    () {
      // Arrange
      const Map<String, Object?> json = <String, Object?>{
        'nonce': _nonce,
        'expiresAt': '2026-07-21T12:15:00+00:00',
      };

      // Act
      final AppHandoffMint mint = AppHandoffMint.fromJson(json);

      // Assert
      expect(mint.nonce, _nonce);
      expect(mint.expiresAt, '2026-07-21T12:15:00+00:00');
      expect(mint.toJson(), json);
    },
  );

  test('AppHandoffDevice omits absent optional fields, never null', () {
    // Arrange
    const AppHandoffDevice device = AppHandoffDevice(platform: 'ios');

    // Act
    final Map<String, Object?> json = device.toJson();

    // Assert
    expect(json, <String, Object?>{'platform': 'ios'});
    expect(json.values, isNot(contains(null)));
  });

  test('AppHandoffDevice round-trips every optional field', () {
    // Arrange
    const Map<String, Object?> json = <String, Object?>{
      'platform': 'android',
      'appVersion': '1.2.3',
      'osVersion': '15',
      'model': 'Pixel 9',
    };

    // Act
    final AppHandoffDevice device = AppHandoffDevice.fromJson(json);

    // Assert
    expect(device.platform, 'android');
    expect(device.appVersion, '1.2.3');
    expect(device.osVersion, '15');
    expect(device.model, 'Pixel 9');
    expect(device.toJson(), json);
  });

  test('AppHandoffRedeemRequest round-trips through JSON', () {
    // Arrange
    const Map<String, Object?> json = <String, Object?>{
      'nonce': _nonce,
      'device': <String, Object?>{'platform': 'android', 'model': 'Pixel 9'},
    };

    // Act
    final AppHandoffRedeemRequest request = AppHandoffRedeemRequest.fromJson(
      json,
    );

    // Assert
    expect(request.nonce, _nonce);
    expect(request.device.platform, 'android');
    expect(request.device.model, 'Pixel 9');
    expect(request.toJson(), json);
  });

  test('AppHandoffRedeemResponse defaults expiresIn to 120 seconds', () {
    // Arrange
    const Map<String, Object?> json = <String, Object?>{
      'token': 'ott',
      'email': 'a@b.com',
    };

    // Act
    final AppHandoffRedeemResponse built = const AppHandoffRedeemResponse(
      token: 'ott',
      email: 'a@b.com',
    );
    final AppHandoffRedeemResponse parsed = AppHandoffRedeemResponse.fromJson(
      json,
    );

    // Assert
    expect(appHandoffTokenExpiresInSeconds, 120);
    expect(built.expiresIn, 120);
    expect(parsed.expiresIn, 120);
  });

  test('AppHandoffRedeemResponse round-trips a sent expiresIn', () {
    // Arrange
    const Map<String, Object?> json = <String, Object?>{
      'token': 'ott',
      'email': 'a@b.com',
      'expiresIn': 60,
    };

    // Act
    final AppHandoffRedeemResponse response = AppHandoffRedeemResponse.fromJson(
      json,
    );

    // Assert
    expect(response.token, 'ott');
    expect(response.email, 'a@b.com');
    expect(response.expiresIn, 60);
    expect(response.toJson(), json);
  });

  test('AppHandoffExpired is the fixed 410 body with the given type', () {
    // Arrange
    const String type = 'https://api.example.com/AppHandoffExpired';

    // Act
    final AppHandoffExpired problem = AppHandoffExpired.withType(type);

    // Assert
    expect(problem.type, type);
    expect(AppHandoffExpired.problemId, 'AppHandoffExpired');
    expect(problem.toJson(), <String, Object?>{
      'type': type,
      'title': 'App handoff expired',
      'status': 410,
      'detail': 'This app handoff is expired or invalid.',
      'data': <String, Object?>{},
    });
  });
}
