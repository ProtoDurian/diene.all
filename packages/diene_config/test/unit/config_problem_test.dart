import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

const ErrorPortal _appPortal = ErrorPortal(
  scheme: 'https',
  host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu',
  platform: 'flutter',
  service: 'app',
  module: 'config',
);

void main() {
  group('ConfigProblemCode', () {
    test('every wire id is snake_case as problemTypeUri requires', () {
      // Arrange
      const List<ConfigProblemCode> codes = ConfigProblemCode.values;

      // Act
      final List<ConfigProblemCode> nonConforming = codes
          .where(
            (ConfigProblemCode code) =>
                !problemWireIdPattern.hasMatch(code.wireId),
          )
          .toList();

      // Assert
      expect(nonConforming, isEmpty);
    });

    test('every code carries a 4xx status', () {
      // Arrange
      const List<ConfigProblemCode> codes = ConfigProblemCode.values;

      // Act
      final List<int> statuses = codes
          .map((ConfigProblemCode code) => code.status)
          .toList();

      // Assert
      expect(
        statuses,
        everyElement(allOf(greaterThanOrEqualTo(400), lessThan(500))),
      );
    });

    test('wire ids are unique', () {
      // Arrange
      const List<ConfigProblemCode> codes = ConfigProblemCode.values;

      // Act
      final Set<String> ids = codes
          .map((ConfigProblemCode code) => code.wireId)
          .toSet();

      // Assert
      expect(ids, hasLength(codes.length));
    });
  });

  group('configProblem', () {
    test('mints its type URI through problemTypeUri', () {
      // Arrange
      const ConfigProblemCode code = ConfigProblemCode.schemaInvalid;

      // Act
      final Problem problem = configProblem(code: code, message: 'invalid');

      // Assert
      expect(
        problem.type,
        problemTypeUri(
          portal: ErrorPortal.localError,
          version: configProblemVersion,
          id: code.wireId,
        ),
      );
    });

    test('defaults to the local-error portal', () {
      // Arrange
      const ConfigProblemCode code = ConfigProblemCode.sourceUnreadable;

      // Act
      final Problem problem = configProblem(code: code, message: 'unreadable');

      // Assert
      expect(problem.type, startsWith('https://local.atomi.cloud/docs/local/'));
    });

    test("honours an application's own portal", () {
      // Arrange
      const ErrorPortal portal = _appPortal;

      // Act
      final Problem problem = configProblem(
        code: ConfigProblemCode.sourceNotAMap,
        message: 'not a map',
        portal: portal,
      );

      // Assert
      expect(
        problem.type,
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/flutter/app/'
        'config/v1/source_not_a_map',
      );
    });

    test('carries the code, status, and detail prefix', () {
      // Arrange
      const ConfigProblemCode code = ConfigProblemCode.landscapeMissing;

      // Act
      final Problem problem = configProblem(
        code: code,
        message: 'no landscape',
      );

      // Assert
      expect(problem.status, 400);
      expect(problem.title, 'no landscape');
      expect(problem.detail, 'config.landscape_missing: no landscape');
      expect(problem.data['code'], 'landscape_missing');
    });

    test('merges extra details alongside the code', () {
      // Arrange
      const Map<String, Object?> details = <String, Object?>{
        'source': 'base.yaml',
      };

      // Act
      final Problem problem = configProblem(
        code: ConfigProblemCode.sourceUnreadable,
        message: 'unreadable',
        details: details,
      );

      // Assert
      expect(problem.data, <String, Object?>{
        'source': 'base.yaml',
        configProblemCodeKey: 'source_unreadable',
        configProblemProvenanceKey: configProblemValue,
      });
    });

    test('stamps the provenance marker under any portal', () {
      // Arrange
      const ConfigProblemCode code = ConfigProblemCode.schemaInvalid;

      // Act
      final Problem local = configProblem(code: code, message: 'invalid');
      final Problem app = configProblem(
        code: code,
        message: 'invalid',
        portal: _appPortal,
      );

      // Assert
      expect(local.data[configProblemProvenanceKey], configProblemValue);
      expect(app.data[configProblemProvenanceKey], configProblemValue);
      expect(configProblemValue, contains(configProblemVersion));
    });

    test('refuses a caller detail that sets a conflicting code', () {
      // Arrange
      const Map<String, Object?> details = <String, Object?>{
        'code': 'source_unreadable',
      };

      // Act
      Problem mint() => configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        details: details,
      );

      // Assert
      expect(
        mint,
        throwsArgumentError,
        reason:
            'a conflicting data.code must never mint a mislabelled envelope',
      );
    });

    test('refuses a caller detail that sets the code even when it agrees', () {
      // Arrange
      const Map<String, Object?> details = <String, Object?>{
        'code': 'schema_invalid',
      };

      // Act
      Problem mint() => configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        details: details,
      );

      // Assert
      expect(mint, throwsArgumentError);
    });

    test('refuses a caller detail that sets the provenance marker', () {
      // Arrange
      const Map<String, Object?> details = <String, Object?>{
        configProblemProvenanceKey: configProblemValue,
      };

      // Act
      Problem mint() => configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        details: details,
      );

      // Assert
      expect(mint, throwsArgumentError);
    });

    test('is never marked recoverable', () {
      // Arrange
      const List<ConfigProblemCode> codes = ConfigProblemCode.values;

      // Act
      final List<bool> recoverable = codes
          .map(
            (ConfigProblemCode code) =>
                configProblem(code: code, message: 'x').recoverable,
          )
          .toList();

      // Assert
      expect(recoverable, everyElement(isFalse));
    });

    test('round-trips through the RFC 9457 JSON envelope', () {
      // Arrange
      final Problem problem = configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        details: <String, Object?>{
          'errors': <String>['app: required block is missing'],
        },
      );

      // Act
      final Problem decoded = Problem.fromJson(problem.toJson());

      // Assert
      expect(decoded, problem);
    });
  });

  group('configFailure', () {
    test('refuses a caller detail that sets the code, like configProblem', () {
      // Arrange
      const Map<String, Object?> details = <String, Object?>{
        'code': 'source_unreadable',
      };

      // Act
      Err<int> mint() => configFailure<int>(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        details: details,
      );

      // Assert
      expect(mint, throwsArgumentError);
    });

    test('wraps the same envelope in an Err', () {
      // Arrange
      const Map<String, Object?> details = <String, Object?>{'block': 'app'};

      // Act
      final Err<int> failure = configFailure<int>(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        portal: _appPortal,
        details: details,
      );

      // Assert
      expect(failure.isErr, isTrue);
      expect(
        failure.problem,
        configProblem(
          code: ConfigProblemCode.schemaInvalid,
          message: 'invalid',
          portal: _appPortal,
          details: details,
        ),
      );
    });
  });

  group('configProblemCode', () {
    test('reads back a config-owned code', () {
      // Arrange
      final Problem problem = configProblem(
        code: ConfigProblemCode.sourceNotAMap,
        message: 'not a map',
      );

      // Act
      final Option<ConfigProblemCode> code = configProblemCode(problem);

      // Assert
      expect(code.isSome, isTrue);
      expect(code.unwrap(), ConfigProblemCode.sourceNotAMap);
    });

    test('returns None for an envelope minted elsewhere', () {
      // Arrange
      const Problem foreign = Problem(
        type: 'https://local.atomi.cloud/docs/local/flutter/app/core/v1/x',
        title: 'foreign',
        status: 400,
        data: <String, Object?>{'util': 'coercion', 'code': 'invalid_input'},
      );

      // Act
      final Option<ConfigProblemCode> code = configProblemCode(foreign);

      // Assert
      expect(code.isNone, isTrue);
    });

    test('classifies a config problem minted under an application portal', () {
      // Arrange
      final Problem problem = configProblem(
        code: ConfigProblemCode.schemaInvalid,
        message: 'invalid',
        portal: _appPortal,
      );

      // Act
      final Option<ConfigProblemCode> code = configProblemCode(problem);

      // Assert
      expect(code.unwrap(), ConfigProblemCode.schemaInvalid);
    });

    test('returns None for a foreign envelope carrying a config-shaped code', () {
      // Arrange
      const Problem foreign = Problem(
        type:
            'https://local.atomi.cloud/docs/local/flutter/app/core/v1/local_error',
        title: 'foreign',
        status: 500,
        data: <String, Object?>{'code': 'schema_invalid'},
      );

      // Act
      final Option<ConfigProblemCode> code = configProblemCode(foreign);

      // Assert
      expect(code.isNone, isTrue);
    });

    test('returns None for a foreign envelope that copies the type URI suffix '
        'and code', () {
      // Arrange
      const Problem foreign = Problem(
        type:
            'https://foreign.example/docs/other/flutter/app/core/v1/schema_invalid',
        title: 'foreign',
        status: 422,
        data: <String, Object?>{'code': 'schema_invalid'},
      );

      // Act
      final Option<ConfigProblemCode> code = configProblemCode(foreign);

      // Assert
      expect(code.isNone, isTrue);
    });

    test('returns None when the provenance marker carries a foreign value', () {
      // Arrange
      const Problem foreign = Problem(
        type:
            'https://foreign.example/docs/other/flutter/app/core/v1/schema_invalid',
        title: 'foreign',
        status: 422,
        data: <String, Object?>{
          'code': 'schema_invalid',
          'x-diene-config-provenance': 'someone_else/pkg@v1',
        },
      );

      // Act
      final Option<ConfigProblemCode> code = configProblemCode(foreign);

      // Assert
      expect(code.isNone, isTrue);
    });

    test('returns None for an envelope minted under a different contract '
        'version', () {
      // Arrange
      final Problem otherVersion = Problem(
        type: problemTypeUri(
          portal: ErrorPortal.localError,
          version: configProblemVersion,
          id: ConfigProblemCode.schemaInvalid.wireId,
        ),
        title: 'v2',
        status: 422,
        data: const <String, Object?>{
          'code': 'schema_invalid',
          'x-diene-config-provenance': 'atomicloud/diene_config@v2',
        },
      );

      // Act
      final Option<ConfigProblemCode> code = configProblemCode(otherVersion);

      // Assert
      expect(code.isNone, isTrue);
    });

    test('returns None for an envelope with no code at all', () {
      // Arrange
      const Problem bare = Problem(
        type: 'about:blank',
        title: 'bare',
        status: 500,
      );

      // Act
      final Option<ConfigProblemCode> code = configProblemCode(bare);

      // Assert
      expect(code.isNone, isTrue);
    });

    test('returns None for a config marker with an unknown code', () {
      // Arrange
      const Problem unknown = Problem(
        type: 'about:blank',
        title: 'unknown',
        status: 422,
        data: <String, Object?>{
          configProblemCodeKey: 'not_a_config_code',
          configProblemProvenanceKey: configProblemValue,
        },
      );

      // Act
      final Option<ConfigProblemCode> code = configProblemCode(unknown);

      // Assert
      expect(code.isNone, isTrue);
    });

    test('recognises every declared code', () {
      // Arrange
      const List<ConfigProblemCode> codes = ConfigProblemCode.values;

      // Act
      final List<ConfigProblemCode> readBack = codes
          .map(
            (ConfigProblemCode code) => configProblemCode(
              configProblem(code: code, message: 'x'),
            ).unwrap(),
          )
          .toList();

      // Assert
      expect(readBack, codes);
    });
  });

  group('configProblemVersion', () {
    test('is a valid contract version segment', () {
      // Arrange
      final RegExp pattern = problemVersionPattern;

      // Act
      final bool matches = pattern.hasMatch(configProblemVersion);

      // Assert
      expect(configProblemVersion, 'v1');
      expect(matches, isTrue);
    });
  });
}
