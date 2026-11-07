import 'package:diene_config/config/app_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

DieneConfig stub({String name = 'installed'}) => ConfigStubBuilder().add(
  appBlock,
  <String, Object?>{'name': name, 'retries': 0, 'tags': <Object?>[]},
).build();

ConfigLoader loaderOf({required String base}) => ConfigLoader(
  base: YamlConfigSource.string(base, name: 'base.yaml'),
  dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
  schema: appSchema(),
);

void main() {
  setUp(AppConfig.reset);
  tearDown(AppConfig.reset);

  group('the compatibility entrypoint', () {
    test('re-exports the whole public surface', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Act
      final String releaseId = c0ConfigContract.provenance.releaseId;

      // Assert
      expect(ConfigProblemCode.schemaInvalid.wireId, 'schema_invalid');
      expect(landscapeDefineKey, 'DIENE_LANDSCAPE');
      expect(releaseId, 'c0-fixtures-r2');
      expect(schema.blocks, hasLength(1));
    });
  });

  group('AppConfig', () {
    test('starts uninstalled', () {
      // Arrange
      AppConfig.reset();

      // Act
      final bool installed = AppConfig.isInstalled;

      // Assert
      expect(installed, isFalse);
      expect(AppConfig.maybeInstance.isNone, isTrue);
    });

    test('throws rather than defaulting when read before install', () {
      // Arrange
      AppConfig.reset();

      // Act
      DieneConfig read() => AppConfig.instance;

      // Assert
      expect(read, throwsStateError);
    });

    test('returns the installed configuration', () {
      // Arrange
      final DieneConfig config = stub();

      // Act
      AppConfig.install(config);

      // Assert
      expect(AppConfig.isInstalled, isTrue);
      expect(AppConfig.instance, same(config));
      expect(AppConfig.maybeInstance.unwrap(), same(config));
    });

    test('refuses a second install by default', () {
      // Arrange
      AppConfig.install(stub());

      // Act
      void installAgain() => AppConfig.install(stub(name: 'second'));

      // Assert
      expect(installAgain, throwsStateError);
      expect(AppConfig.instance.slice(appBlock).name, 'installed');
    });

    test('replaces on an explicit force', () {
      // Arrange
      AppConfig.install(stub());

      // Act
      AppConfig.install(stub(name: 'forced'), force: true);

      // Assert
      expect(AppConfig.instance.slice(appBlock).name, 'forced');
    });

    test('reset clears the holder', () {
      // Arrange
      AppConfig.install(stub());

      // Act
      AppConfig.reset();

      // Assert
      expect(AppConfig.isInstalled, isFalse);
      expect(() => AppConfig.instance, throwsStateError);
    });
  });

  group('AppConfig.loadAndInstall', () {
    test('installs the configuration a successful load produced', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base: 'app:\n  name: loaded\n  retries: 1\n',
      );

      // Act
      final Result<DieneConfig> loaded = await AppConfig.loadAndInstall(loader);

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(AppConfig.isInstalled, isTrue);
      expect(AppConfig.instance.slice(appBlock).name, 'loaded');
      expect(AppConfig.instance, same(loaded.unwrap()));
    });

    test('installs nothing when the load fails', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base: 'app:\n  name: bad\n  retries: -1\n',
      );

      // Act
      final Result<DieneConfig> loaded = await AppConfig.loadAndInstall(loader);

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(AppConfig.isInstalled, isFalse);
    });

    test(
      'refuses to replace an installed configuration without force',
      () async {
        // Arrange
        AppConfig.install(stub());
        final ConfigLoader loader = loaderOf(
          base: 'app:\n  name: second\n  retries: 0\n',
        );

        // Act
        final Future<Result<DieneConfig>> loading = AppConfig.loadAndInstall(
          loader,
        );

        // Assert
        await expectLater(loading, throwsStateError);
        expect(AppConfig.instance.slice(appBlock).name, 'installed');
      },
    );

    test('replaces an installed configuration on force', () async {
      // Arrange
      AppConfig.install(stub());
      final ConfigLoader loader = loaderOf(
        base: 'app:\n  name: replaced\n  retries: 0\n',
      );

      // Act
      final Result<DieneConfig> loaded = await AppConfig.loadAndInstall(
        loader,
        force: true,
      );

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(AppConfig.instance.slice(appBlock).name, 'replaced');
    });
  });
}
