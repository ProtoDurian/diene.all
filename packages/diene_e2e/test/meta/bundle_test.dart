import 'package:diene_api_engine/diene_api_engine.dart' as api;
import 'package:diene_api_engine/test_helper.dart' as api_helper;
import 'package:diene_auth_engine/diene_auth_engine.dart' as auth;
import 'package:diene_auth_engine/test_helper.dart' as auth_helper;
import 'package:diene_config/diene_config.dart' as config;
import 'package:diene_config/test_helper.dart' as config_helper;
import 'package:diene_core_utils/diene_core_utils.dart' as core_utils;
import 'package:diene_e2e/diene_e2e.dart' as e2e;
import 'package:diene_e2e/test_helper.dart' as e2e_helper;
import 'package:diene_interfaces/diene_interfaces.dart' as interfaces;
import 'package:diene_interfaces/test_helper.dart' as interfaces_helper;
import 'package:diene_problems/diene_problems.dart' as problems;
import 'package:diene_problems/test_helper.dart' as problems_helper;
import 'package:diene_result/diene_result.dart' as result;
import 'package:diene_result/test_helper.dart' as result_helper;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('helper passthroughs resolve to the member symbol', () {
    final Map<String, List<(Object, Object)>> passthroughs =
        <String, List<(Object, Object)>>{
          'diene_result': <(Object, Object)>[
            (e2e_helper.expectOk, result_helper.expectOk),
            (e2e_helper.expectErr, result_helper.expectErr),
            (e2e_helper.expectSome, result_helper.expectSome),
            (e2e_helper.expectNone, result_helper.expectNone),
            (e2e_helper.TestHelperFailure, result_helper.TestHelperFailure),
          ],
          'diene_problems': <(Object, Object)>[
            (e2e_helper.expectProblem, problems_helper.expectProblem),
            (e2e_helper.aProblem, problems_helper.aProblem),
            (
              e2e_helper.ProblemMatcherError,
              problems_helper.ProblemMatcherError,
            ),
          ],
          'diene_interfaces': <(Object, Object)>[
            (e2e_helper.InMemorySystem, interfaces_helper.InMemorySystem),
            (e2e_helper.InMemoryVfs, interfaces_helper.InMemoryVfs),
          ],
          'diene_config': <(Object, Object)>[
            (e2e_helper.FakeConfigSource, config_helper.FakeConfigSource),
            (e2e_helper.ConfigStubBuilder, config_helper.ConfigStubBuilder),
            (e2e_helper.expectOkConfig, config_helper.expectOkConfig),
          ],
          'diene_auth_engine': <(Object, Object)>[
            (e2e_helper.FakeAuth, auth_helper.FakeAuth),
            (e2e_helper.FakeAppHandoffApi, auth_helper.FakeAppHandoffApi),
            (
              e2e_helper.FakeInstallReferrerSource,
              auth_helper.FakeInstallReferrerSource,
            ),
          ],
          'diene_api_engine': <(Object, Object)>[
            (e2e_helper.FakeHttpTransport, api_helper.FakeHttpTransport),
            (e2e_helper.okJson, api_helper.okJson),
            (e2e_helper.expectProblemType, api_helper.expectProblemType),
          ],
        };

    passthroughs.forEach((String member, List<(Object, Object)> pairs) {
      test(member, () {
        // Arrange
        final List<(Object, Object)> symbols = pairs;

        // Act
        final List<bool> same = <bool>[
          for (final (Object bundled, Object own) in symbols)
            identical(bundled, own) || bundled == own,
        ];

        // Assert
        expect(same, everyElement(isTrue));
      });
    });

    test('exactly the six members with a helper are passed through', () {
      // Arrange
      final Set<String> members = passthroughs.keys.toSet();

      // Act
      final bool hasCoreUtils = members.contains('diene_core_utils');

      // Assert
      expect(members, hasLength(6));
      expect(hasCoreUtils, isFalse);
    });
  });

  group('a name two members declare goes to the contract owner', () {
    test('expectOk and expectErr are the result helpers', () {
      // Arrange
      const result.Result<int> ok = result.Ok<int>(3);

      // Act
      final int value = e2e_helper.expectOk(ok);

      // Assert
      expect(value, 3);
      expect(identical(e2e_helper.expectOk, api_helper.expectOk), isFalse);
      expect(identical(e2e_helper.expectErr, api_helper.expectErr), isFalse);
      expect(
        () => e2e_helper.expectOk(
          const result.Err<int>(
            problems.Problem(type: 'urn:test:e', title: 'e', status: 500),
          ),
        ),
        throwsA(isA<result_helper.TestHelperFailure>()),
      );
    });

    test('FakeAuth is the auth engine fake', () {
      // Arrange
      final e2e_helper.FakeAuth fake = e2e_helper.FakeAuth(
        <Map<auth.ResourceKey, result.Result<auth.ResourceToken>>>[
          <auth.ResourceKey, result.Result<auth.ResourceToken>>{},
        ],
      );

      // Act
      final Type type = fake.runtimeType;

      // Assert
      expect(type, auth_helper.FakeAuth);
      expect(type == api_helper.FakeAuth, isFalse);
      expect(fake, isA<auth.IAuth>());
    });
  });

  test(
    'the runtime bundle carries every member symbol, core utils included',
    () {
      // Arrange
      final List<(Object, Object)> pairs = <(Object, Object)>[
        (e2e.Problem, problems.Problem),
        (e2e.Result, result.Result),
        (e2e.System, interfaces.System),
        (e2e.slugify, core_utils.slugify),
        (e2e.ConfigSource, config.ConfigSource),
        (e2e.DeferredLoginOutcome, auth.DeferredLoginOutcome),
        (e2e.AppHandoffCarrier, auth.AppHandoffCarrier),
        (e2e.ApiEngine, api.ApiEngine),
      ];

      // Act
      final List<bool> same = <bool>[
        for (final (Object bundled, Object own) in pairs)
          identical(bundled, own) || bundled == own,
      ];

      // Assert
      expect(same, everyElement(isTrue));
    },
  );
}
