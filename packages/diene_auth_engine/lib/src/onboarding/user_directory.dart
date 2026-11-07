/// A backend's `/User` onboarding surface; returns raw status codes.
abstract interface class UserDirectory {
  /// `GET /User/Me`: 200 when the user exists, 404 to create.
  Future<int> getUserMe({
    required String backendId,
    required String accessToken,
  });

  /// `POST /User` with the ID and access tokens; 2xx or 409 means done.
  Future<int> postUser({
    required String backendId,
    required String accessToken,
    required String idToken,
  });
}
