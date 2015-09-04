library a_la_carte.server.oauth2_policy_validator;

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:d17/d17.dart';
import 'package:oauth2/oauth2.dart' as oauth2;

import 'db_backend.dart';
import 'authenticator.dart';
import 'local_session_data.dart';
import 'permission_getter.dart';
import 'logger.dart';

class OAuth2Authenticator extends Authenticator {
  // TODO: Move this to a config file.
  @Inject(name: 'a_la_carte.server.oauth2_policy_validator.oauth2ClientId')
  String _oauth2ClientId;

  @Inject(name: 'a_la_carte.server.oauth2_policy_validator.oauth2ClientSecret')
  String _oauth2ClientSecret;

  @Inject(
      name:
          'a_la_carte.server.oauth2_policy_validator.oauth2AuthorizationEndpoint')
  String _oauth2AuthorizationEndpoint;

  @Inject(name: 'a_la_carte.server.oauth2_policy_validator.oauth2TokenEndpoint')
  String _oauth2TokenEndpoint;

  @Inject(name: 'a_la_carte.server.oauth2_policy_validator.oauth2Redirect')
  String _oauth2Redirect;

  @Inject(name: 'a_la_carte.server.auth_policy_validator.auth_doc_name')
  String _authorizationDocName;

  @InjectProxy(from: DbBackend) RetrievePermissions _retrievePermissions;

  @inject
  Logger defaultLogger;

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
        rethrow;
      }
    }
  }

  @override
  Future validateMethodIsPermittedOnResource(String method, Uri uri,
      DbBackend dataStore, LocalSessionData session) async {
    if (method == 'GET' || method == 'HEAD') {
      return null;
    } else {
      if (session.email == null) {
        return prepareUnauthorizedRequest(dataStore);
      }
      List roles = await _retrievePermissions(dataStore, session.email, _authorizationDocName);
      if (roles.contains('write') || roles.contains('admin')) {
        return null;
      }
      return prepareUnauthorizedRequest(dataStore);
    }
  }

  @override
  Future<AuthenticatorIdentity> createEmptyPolicyIdentity(
      String psid, String serviceAccount) async {
    return new OAuth2AuthenticatorIdentity(null, serviceAccount);
  }

  Future<AuthenticatorIdentity> createPolicyIdentityFromState(
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

  Future<AuthenticatorIdentity> _createPolicyIdentityFromCredentialedClient(
      String psid,
      String serviceAccount,
      oauth2.Client client,
      String tsid,
      int currentTimeInMillisecondsSinceEpoch) async {
    var response =
        await client.get('https://www.googleapis.com/oauth2/v2/userinfo');
    final JsonDecoder jsonDecoder = new JsonDecoder();
    final responseMap = jsonDecoder.convert(response.body);
    final identity = new OAuth2AuthenticatorIdentity(psid, serviceAccount)
      ..email = responseMap['email']
      ..fullName = responseMap['name']
      ..picture = responseMap['picture'];
    return identity;
  }
}

class OAuth2AuthenticatorIdentity extends AuthenticatorIdentity {
  final String id;
  final String serviceAccount;

  String email;
  String fullName;
  String picture;
  OAuth2AuthenticatorIdentity(String this.id, String this.serviceAccount);
}
