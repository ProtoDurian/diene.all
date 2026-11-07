/// Wraps generated OpenAPI SDKs and raw calls into `Result<T>`, registers N
/// backends with per-backend auth, retries once on a network failure and runs
/// a dormant same-landscape address rescue.
library;

export 'package:diene_auth_engine/diene_auth_engine.dart'
    show IAuth, ResourceKey, ResourceToken;
export 'package:diene_problems/diene_problems.dart' show Problem;
export 'package:diene_result/diene_result.dart' show Err, Ok, Result;

export 'src/bridge.dart'
    show BridgeProblems, isProblemJson, toResult, tryDecodeObject;
export 'src/client_tree.dart' show ClientTree;
export 'src/config.dart'
    show ApiEngineConfig, BackendConfig, LpsmCoordinate, RescueConfig;
export 'src/engine.dart' show ApiEngine, Backend, BackendClientAdapter;
export 'src/oa3/sdk_adapter.dart' show ResultSdk;
export 'src/rescue/docs.dart' show DocA, DocC;
export 'src/rescue/router.dart'
    show RescueOutcome, RescueRouter, RescueUnavailable, Rescued;
export 'src/rescue/store.dart'
    show FileRescueStore, InMemoryRescueStore, RescueStore;
export 'src/transport.dart'
    show
        HttpMethod,
        HttpRequest,
        HttpResponse,
        HttpTransport,
        IoHttpTransport,
        NetworkFailure,
        Received,
        RetryOnceTransport,
        TransportOutcome;
