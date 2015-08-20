part of a_la_carte.server;

class PolicyStateError extends Error {
  final String redirectUri;
  final String awakenId;
  final String awakenRev;
  final Map replyFromDbBackend;
  PolicyStateError.redirect(
      String this.redirectUri, String this.awakenId, String this.awakenRev)
      : replyFromDbBackend = new Map();

  PolicyStateError(Map this.replyFromDbBackend)
      : redirectUri = null,
        awakenId = null,
        awakenRev = null;
}

abstract class PolicyIdentity {
  String get id;
  String get serviceAccount;
  String get email;
  String get fullName;
  String get picture;
}

abstract class PolicyValidator extends Object {
  Future validateMethodIsPermittedOnResource(
      String method, Uri uri, DbBackend dataStore);
  Future prepareUnauthorizedRequest(DbBackend dataStore);
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
  Future<PolicyIdentity> createEmptyPolicyIdentity(
      String psid, String serviceAccount);
  Future<PolicyIdentity> createPolicyIdentityFromState(
      Future<SessionClientRow> sessionFuture,
      String serviceAccount,
      DbBackend dbBackend,
      {String code: null});
}

class OAuth2PolicyValidator extends PolicyValidator {
  // TODO: Move this to a config file.
  static const String _oauth2ClientId =
      '121943999603-3spq3v4u3ad49v67go56pe5t6t5o0ivu.apps.googleusercontent.com';
  static const String _oauth2ClientSecret = 'XH7Vsmfeb_Jl9Ywf3Ng6TSTP';
  static const String _oauth2AuthorizationEndpoint =
      'https://accounts.google.com/o/oauth2/auth';
  static const String _oauth2TokenEndpoint =
      'https://accounts.google.com/o/oauth2/token';
  static const String _oauth2Redirect =
      'http://www.a-la-carte.com:8080/_auth/landing';

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
  Future prepareUnauthorizedRequest(DbBackend dataStore) async {
    final watchMessage = new Uuid().v4();
    try {
      var replyMap = await dataStore.makeServicePut(
          Uri.parse('/a_la_carte/$watchMessage'),
          {'type': 'authentication_attempt'});
      final revId = replyMap['rev'];
      final grant = new oauth2.AuthorizationCodeGrant(
          _oauth2ClientId,
          _oauth2ClientSecret,
          Uri.parse(_oauth2AuthorizationEndpoint),
          Uri.parse(_oauth2TokenEndpoint));
      throw new PolicyStateError.redirect(
          grant
              .getAuthorizationUrl(Uri.parse(_oauth2Redirect),
                  scopes: ['profile', 'email'], state: '$watchMessage,$revId')
              .toString(),
          watchMessage,
          revId);
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

  @override
  Future validateMethodIsPermittedOnResource(
      String method, Uri uri, DbBackend dataStore) async {
    if (method == 'GET' || method == 'HEAD') {
      return null;
    } else {
      prepareUnauthorizedRequest(dataStore);
    }
  }

  @override
  Future<PolicyIdentity> createEmptyPolicyIdentity(
      String psid, String serviceAccount) {
    return new Future.value(new OAuth2PolicyIdentity(null, serviceAccount));
  }

  Future<PolicyIdentity> createPolicyIdentityFromState(
      Future<SessionClientRow> sessionFuture,
      String serviceAccount,
      DbBackend dbBackend,
      int currentTimeInMillisecondsSinceEpoch,
      {String code: null,
      String notifyOnAuth: null,
      bool isPassivePush: false}) async {
    String rev = null;
    Map psidState = null;
    int expirationClock = null;
    final session = await sessionFuture;
    final psid = session.psid;

    final psidUri = Uri.parse('/a_la_carte/${Uri.encodeComponent(psid)}');

    try {
      psidState = await dbBackend.makeServiceGet(psidUri);
      rev = psidState['_rev'];
      assert(psidState['type'] == 'persistent_session');
      expirationClock = psidState['expiration'];
    } catch (error) {
      if (error is ServiceError && error.result['error'] == 'not_found') {
      } else {
        throw error;
      }
    }

    oauth2.Client client;
    bool clientIsNew = false;
    final grant = new oauth2.AuthorizationCodeGrant(
        _oauth2ClientId,
        _oauth2ClientSecret,
        Uri.parse(_oauth2AuthorizationEndpoint),
        Uri.parse(_oauth2TokenEndpoint));

    if (code != null) {
      grant.getAuthorizationUrl(Uri.parse(_oauth2Redirect),
          scopes: ['profile', 'email'], state: notifyOnAuth);
      client = await grant
          .handleAuthorizationResponse({'code': code, 'state': notifyOnAuth});
      clientIsNew = true;
    } else if (psidState != null) {
      client = new oauth2.Client(
          grant.identifier,
          grant.secret,
          new oauth2.Credentials.fromJson(
              new JsonEncoder().convert(psidState)));
      if (client.credentials.isExpired) {
        client = await client.refreshCredentials();
        clientIsNew = true;
      }
    }

    if (client != null) {
      if (clientIsNew) {
        Map credentials =
            new JsonDecoder().convert(client.credentials.toJson());
        credentials['type'] = 'persistent_session';
        if (rev != null) {
          credentials['_rev'] = rev;
        }
        dbBackend.makeServicePut(psidUri, credentials);
      }
      if (notifyOnAuth != null) {
        final originalDocumentIdAndRev = notifyOnAuth.split(',');
        final originalDocumentId = originalDocumentIdAndRev[0];
        final originalDocumentRev = originalDocumentIdAndRev[1];
        dbBackend.makeServiceDelete(
            Uri.parse('/a_la_carte/$originalDocumentId'), originalDocumentRev);
      }
      return await _createPolicyIdentityFromCredentialedClient(
          psid,
          serviceAccount,
          client,
          session,
          session.tsid,
          currentTimeInMillisecondsSinceEpoch,
          isPassivePush: isPassivePush);
    }
    return await prepareUnauthorizedRequest(dbBackend);
  }

  Future<PolicyIdentity> _createPolicyIdentityFromExistingState(String psid,
      {String accessToken: null,
      String refreshToken: null,
      String tokenEndpoint: null,
      List<String> scopes: const <String>[],
      int expiration: 0}) {}

  Future<PolicyIdentity> _createPolicyIdentityFromCredentialedClient(
      String psid,
      String serviceAccount,
      oauth2.Client client,
      SessionClient sessionClient,
      String tsid,
      int currentTimeInMillisecondsSinceEpoch,
      {bool isPassivePush: false}) async {
    var response =
        await client.get('https://www.googleapis.com/oauth2/v2/userinfo');
    final JsonDecoder jsonDecoder = new JsonDecoder();
    final responseMap = jsonDecoder.convert(response.body);
    final identity = new OAuth2PolicyIdentity(psid, serviceAccount)
      ..email = responseMap['email']
      ..fullName = responseMap['name']
      ..picture = responseMap['picture'];
    sessionClient.pushClientAuthorizationToListener(
        tsid, currentTimeInMillisecondsSinceEpoch, psid, identity,
        isPassivePush: isPassivePush);
    return identity;
  }
}

class OAuth2PolicyIdentity extends PolicyIdentity {
  final String id;
  final String serviceAccount;

  String email;
  String fullName;
  String picture;
  OAuth2PolicyIdentity(String this.id, String this.serviceAccount);
}
