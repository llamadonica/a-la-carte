part of a_la_carte.server;

class PolicyStateError extends Error {
  final String redirectUri;
  final String awakenUuid;
  final Map replyFromDbBackend;
  PolicyStateError.redirect(String this.redirectUri, String this.awakenUuid)
      : replyFromDbBackend = new Map();

  PolicyStateError(Map this.replyFromDbBackend)
      : redirectUri = null,
        awakenUuid = null;
}

abstract class PolicyIdentity {
  String get id;
  String get serviceAccount;
}

abstract class PolicyValidator extends Object {
  Future validateMethodIsPermittedOnResource(
      String method, Uri uri, PolicyIdentity identity, DbBackend dataStore);
  Future convoluteUnchunkedRequest(
      HttpClientRequest request, PolicyIdentity identity, String addCookie);
  Future convoluteChunkedRequest(
      HttpClientRequest request, PolicyIdentity identity, String addCookie);

  Future hijackUnauthorizedMethod(
      Stream<List<int>> input,
      StreamSink<List<int>> output,
      String method,
      Uri uri,
      Map<String, Object> headers);
  Future<PolicyIdentity> createEmptyPolicyIdentity(String serviceAccount);
}

class OAuth2PolicyValidator extends PolicyValidator {
  // TODO: Move this to a config file.
  static const String _oauth2ClientId =
      '121943999603-3spq3v4u3ad49v67go56pe5t6t5o0ivu.apps.googleusercontent.com';
  static const String _oauth2ClientSecret = 'XH7Vsmfeb_Jl9Ywf3Ng6TSTP';
  static const String _oauth2AuthorizationEndpoint =
      'https://accounts.google.com/o/oauth2/auth';
  static const String _oauth2TokenEndpoint = 'https://accounts.google.com/o/oauth2/token';
  static const String _oauth2Redirect = 'http://localhost:8080/_auth/landing';

  @override
  Future convoluteChunkedRequest(
      HttpClientRequest request, PolicyIdentity identity, String addCookie) {
    // TODO: implement convoluteChunkedRequest
  }

  @override
  Future convoluteUnchunkedRequest(
      HttpClientRequest request, PolicyIdentity identity, String addCookie) {
    // TODO: implement convoluteUnchunkedRequest
  }

  @override
  Future hijackUnauthorizedMethod(
      Stream<List<int>> input,
      StreamSink<List<int>> output,
      String method,
      Uri uri,
      Map<String, Object> headers) {
    // TODO: implement hijackUnauthorizedMethod
  }

  @override
  Future validateMethodIsPermittedOnResource(String method, Uri uri,
      PolicyIdentity identity, DbBackend dataStore) async {
    if (method == 'GET' || method == 'HEAD') {
      return null;
    } else {
      final watchMessage = new Uuid().v4();
      try {
        await dataStore.makeServicePut(Uri.parse('/a_la_carte/$watchMessage'),
            {'type': 'authentication_attempt'});
        final grant = new oauth2.AuthorizationCodeGrant(
            _oauth2ClientId,
            _oauth2ClientSecret,
            Uri.parse(_oauth2AuthorizationEndpoint),
            Uri.parse(_oauth2TokenEndpoint));
        throw new PolicyStateError.redirect(
            grant
                .getAuthorizationUrl(Uri.parse(_oauth2Redirect),
                    scopes: ['profile', 'email'], state: watchMessage)
                .toString(),
            watchMessage);
      } catch (error, stackTrace) {
        if (error is ServiceError) {
          error.result['message'] =
              'I couldn\'t log in a user because I couldn\'t get the list of'
              ' authorized users from the database.';
          throw new PolicyStateError(error.result);
        } else {
          throw error;
        }
      }
    }
  }

  @override
  Future<PolicyIdentity> createEmptyPolicyIdentity(String serviceAccount) {
    return new Future.value(new OAuth2PolicyIdentity(null, serviceAccount));
  }

  @override
  Future<PolicyIdentity> createPolicyIdentityFromState(
      String code, String uuid, String serviceAccount) async {
    final grant = new oauth2.AuthorizationCodeGrant(
        _oauth2ClientId,
        _oauth2ClientSecret,
        Uri.parse(_oauth2AuthorizationEndpoint),
        Uri.parse(_oauth2TokenEndpoint));
    try {
      grant.getAuthorizationUrl(Uri.parse(_oauth2Redirect), scopes: ['profile', 'email'], state: uuid);
      oauth2.Client client = await grant.handleAuthorizationResponse({'code': code, 'state': uuid});
      var response = await client.get('https://www.googleapis.com/oauth2/v2/userinfo');
      print(response.body);
    } catch (error) {
      print(error.toString());
    }
    return null;
  }
}

class OAuth2PolicyIdentity extends PolicyIdentity {
  final String id;
  final String serviceAccount;
  OAuth2PolicyIdentity(String this.id, String this.serviceAccount);
}
