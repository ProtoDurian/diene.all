// Production dead-code root: references the whole public surface.
import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';

const List<Object?> _publicSurface = <Object?>[
  appHandoffCarrierScheme,
  appHandoffCarrierVersion,
  appHandoffDefaultMount,
  appHandoffNonceLength,
  appHandoffRedeemPath,
  appHandoffReferrerField,
  appHandoffTokenExpiresInSeconds,
  buildAppHandoffCarrier,
  buildAppHandoffInstallReferrer,
  isValidAppHandoffNonce,
  parseAppHandoffCarrier,
  parseAppHandoffClipboard,
  parseAppHandoffInstallReferrer,
  AppHandoffDevice,
  AppHandoffExpired,
  AppHandoffMint,
  AppHandoffNonceState,
  AppHandoffRedeemRequest,
  AppHandoffRedeemResponse,
  AppHandoffStub,
  AppHandoffUser,
  DeferredLoginJourney,
  DeferredLoginJourneyOutcome,
  DeferredLoginResult,
  Journey,
  JourneyAssertionError,
  JourneyResult,
  JourneyStep,
  JourneyStepResult,
  StubHandler,
  StubRequest,
  StubResponse,
  StubServer,
  expectEquals,
  expectJourneyFailedAt,
  expectJourneyOk,
  expectTrue,
];

void main() {
  if (_publicSurface.isEmpty) {
    throw StateError('the public surface must be referenced');
  }
}
