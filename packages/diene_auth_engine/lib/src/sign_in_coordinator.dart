import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'auth/session_controller.dart';
import 'home/home_claim.dart';
import 'onboarding/onboarding_phase.dart';
import 'returnto/return_to.dart';

/// The outcome of a full sign-in.
final class SignInResult {
  const SignInResult({
    required this.home,
    required this.phases,
    this.continueTo,
  });

  final HomeResolution home;

  /// Each backend's onboarding result.
  final Map<String, Result<OnboardingPhase>> phases;

  /// The exact route to resume, if any.
  final Uri? continueTo;
}

/// Runs sign-in: home claim, login, onboarding, claim confirm, returnTo.
///
/// A Doc B pick is never cached as the home; only a fresh JWT claim is.
final class SignInCoordinator {
  const SignInCoordinator({
    required this._session,
    required this._homeResolver,
    required this._onboarding,
  });

  final SessionController _session;
  final HomeClaimResolver _homeResolver;
  final MultiBackendOnboarding _onboarding;

  Future<Result<SignInResult>> signIn({
    Map<String, String> extraParams = const <String, String>{},
    String? preferredLandscape,
    Uri? returnTo,
  }) async {
    final Result<HomeResolution> homeResult = await _homeResolver.resolve(
      preferred: preferredLandscape,
    );
    if (homeResult is Err<HomeResolution>) {
      return Err<SignInResult>(homeResult.problem);
    }
    HomeResolution home = (homeResult as Ok<HomeResolution>).value;

    final Result<Object?> login = await _session.signIn(
      extraParams: extraParams,
    );
    if (login is Err) {
      return Err<SignInResult>(login.problem);
    }

    // The issued token's claim overrides the pre-login value.
    final Result<String?> issued = await _homeResolver.authoritativeHome();
    if (issued is Err<String?>) {
      return Err<SignInResult>(issued.problem);
    }
    final String? issuedHome = (issued as Ok<String?>).value;
    if (issuedHome != null) {
      home = HomeResolution(
        landscape: issuedHome,
        kind: HomeResolutionKind.fromClaim,
      );
      await _homeResolver.commit(issuedHome);
    }

    final Map<String, Result<OnboardingPhase>> phases = await _onboarding
        .runAll();

    if (home.kind == HomeResolutionKind.selected) {
      for (final MapEntry<String, Result<OnboardingPhase>> entry
          in phases.entries) {
        final Result<OnboardingPhase> outcome = entry.value;
        if (outcome is Err<OnboardingPhase>) {
          return Err<SignInResult>(outcome.problem);
        }
      }
      final Result<String?> confirmed = await _homeResolver.confirmedHome();
      if (confirmed is Err<String?>) {
        return Err<SignInResult>(confirmed.problem);
      }
      final String? confirmedHome = (confirmed as Ok<String?>).value;
      if (confirmedHome == null) {
        return const Err<SignInResult>(
          Problem(
            type: 'urn:diene:problem:home-claim-unconfirmed',
            title: 'Home landscape claim not confirmed after onboarding',
            status: 409,
            recoverable: true,
          ),
        );
      }
      home = HomeResolution(
        landscape: confirmedHome,
        kind: HomeResolutionKind.fromClaim,
      );
      await _homeResolver.commit(confirmedHome);
    }

    final Uri? continueTo = returnTo == null
        ? null
        : ReturnTo.capture(
            returnTo,
          ).match(ok: (_) => returnTo, err: (_) => null);

    return Ok<SignInResult>(
      SignInResult(home: home, phases: phases, continueTo: continueTo),
    );
  }
}
