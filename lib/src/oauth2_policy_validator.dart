library a_la_carte.server.oauth2_policy_validator;

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:oauth2/oauth2.dart' as oauth2;

import 'db_backend.dart';
import 'policy_validator.dart';
import 'local_session_data.dart';


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
    } catch (error) {
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
  Future validateMethodIsPermittedOnResource(String method, Uri uri,
                                             DbBackend dataStore, LocalSessionData session) async {
    if (method == 'GET' || method == 'HEAD') {
      return null;
    } else {
      return prepareUnauthorizedRequest(dataStore);
    }
  }

  @override
  Future<PolicyIdentity> createEmptyPolicyIdentity(
      String psid, String serviceAccount) async {
    return new OAuth2PolicyIdentity(null, serviceAccount);
  }

  Future<PolicyIdentity> createPolicyIdentityFromState(
      LocalSessionData session,
      String serviceAccount,
      DbBackend dbBackend,
      int currentTimeInMillisecondsSinceEpoch,
      {String code: null,
      String notifyOnAuth: null,
      bool alsoCheckPassivePath: true}) async {
    String rev = null;
    final psid = session.psid;
    int expirationClock = null;
    Future<Map> _psidState;
    bool psidStateIsSet = false;
    final psidUri = Uri.parse('/a_la_carte/${Uri.encodeComponent(psid)}');
    Future<Map> loadPsidState() async {
      try {
        final psidState = await dbBackend.makeServiceGet(psidUri);
        rev = psidState['_rev'];
        assert(psidState['type'] == 'persistent_session');
        expirationClock = psidState['expiration'];
        return psidState;
      } catch (error) {
        if (error is ServiceError && error.result['error'] == 'not_found') {
          return null;
        } else {
          throw error;
        }
      }
    }
    Future<Map> getPsidState() {
      if (!psidStateIsSet) {
        _psidState = loadPsidState();
      }
      return _psidState;
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
    } else if (alsoCheckPassivePath && (await getPsidState()) != null) {
      client = new oauth2.Client(
          grant.identifier,
          grant.secret,
          new oauth2.Credentials.fromJson(
              new JsonEncoder().convert(_psidState)));
      if (client.credentials.isExpired && client.credentials.canRefresh) {
        client = await client.refreshCredentials();
        clientIsNew = true;
      } else if (client.credentials.isExpired) {
        client = null;
      }
    }

    if (client != null) {
      if (clientIsNew) {
        final Map psidState = await getPsidState();
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
      final identity = await _createPolicyIdentityFromCredentialedClient(
          psid,
          serviceAccount,
          client,
          session.tsid,
          currentTimeInMillisecondsSinceEpoch);
      return identity;
    }
    return null;
  }

  Future<PolicyIdentity> _createPolicyIdentityFromCredentialedClient(
      String psid,
      String serviceAccount,
      oauth2.Client client,
      String tsid,
      int currentTimeInMillisecondsSinceEpoch) async {
    var response =
    await client.get('https://www.googleapis.com/oauth2/v2/userinfo');
    final JsonDecoder jsonDecoder = new JsonDecoder();
    final responseMap = jsonDecoder.convert(response.body);
    final identity = new OAuth2PolicyIdentity(psid, serviceAccount)
      ..email = responseMap['email']
      ..fullName = responseMap['name']
      ..picture = responseMap['picture'];
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
