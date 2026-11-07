import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import '../auth/claims.dart';
import 'landscape_selector.dart';

/// Reads the `home_landscape` claim from the JWT; `null` when absent.
typedef HomeClaimReader = Future<String?> Function();

/// A [HomeClaimReader] that decodes the claim from the token [readToken] gives.
HomeClaimReader jwtHomeClaimReader(Future<String?> Function() readToken) =>
    () async {
      final String? token = await readToken();
      if (token == null || token.isEmpty) {
        return null;
      }
      return Claims.home(Claims.decode(token));
    };

/// A local cache of the home claim; it never decides the home.
abstract interface class HomeClaimStore {
  Future<String?> read();
  Future<void> write(String landscape);
  Future<void> clear();
}

enum HomeResolutionKind {
  /// The claim was present; Doc B was not fetched.
  fromClaim,

  /// The claim was absent; Doc B selection ran.
  selected,
}

final class HomeResolution {
  const HomeResolution({required this.landscape, required this.kind});

  final String landscape;
  final HomeResolutionKind kind;
}

/// Resolves the home landscape on every sign-in from the JWT claim.
///
/// Doc B is fetched only while the claim is absent; the cache never decides.
final class HomeClaimResolver {
  const HomeClaimResolver({
    required this._claimReader,
    required this._selector,
    this._store,
    this._forcedClaimReader,
  });

  final HomeClaimReader _claimReader;
  final LandscapeSelectorClient _selector;
  final HomeClaimStore? _store;

  final HomeClaimReader? _forcedClaimReader;

  /// The JWT claim without running Doc B; `Ok(null)` when absent.
  Future<Result<String?>> authoritativeHome() async {
    try {
      final String? claim = await _claimReader();
      return Ok<String?>(claim != null && claim.isNotEmpty ? claim : null);
    } on Object catch (error) {
      return Err<String?>(
        Problem(
          type: 'urn:diene:problem:home-claim-read',
          title: 'Could not read the home landscape claim',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
  }

  /// The claim from a fresh token after onboarding; `Ok(null)` fails closed.
  Future<Result<String?>> confirmedHome() async {
    final HomeClaimReader? reader = _forcedClaimReader;
    if (reader == null) {
      return const Ok<String?>(null);
    }
    try {
      final String? claim = await reader();
      return Ok<String?>(claim != null && claim.isNotEmpty ? claim : null);
    } on Object catch (error) {
      return Err<String?>(
        Problem(
          type: 'urn:diene:problem:home-claim-read',
          title: 'Could not read the home landscape claim',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
  }

  /// Uses the claim when present, otherwise runs Doc B selection.
  Future<Result<HomeResolution>> resolve({String? preferred}) async {
    final Result<String?> read = await authoritativeHome();
    if (read is Err<String?>) {
      return Err<HomeResolution>(read.problem);
    }
    final String? authoritative = (read as Ok<String?>).value;
    if (authoritative != null && authoritative.isNotEmpty) {
      await _mirror(authoritative);
      return Ok<HomeResolution>(
        HomeResolution(
          landscape: authoritative,
          kind: HomeResolutionKind.fromClaim,
        ),
      );
    }
    final Result<String> selected = await _selector.selectHome(
      preferred: preferred,
    );
    return selected.map(
      (String landscape) => HomeResolution(
        landscape: landscape,
        kind: HomeResolutionKind.selected,
      ),
    );
  }

  /// Caches the claim written by onboarding.
  Future<void> commit(String landscape) => _mirror(landscape);

  /// Clears the cached home.
  Future<void> forget() async => _store?.clear();

  Future<void> _mirror(String landscape) async {
    final HomeClaimStore? store = _store;
    if (store == null) {
      return;
    }
    try {
      await store.write(landscape);
    } on Object {
      // The cache never overrides the JWT.
    }
  }
}
