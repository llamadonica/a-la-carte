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
  Future prepareUnauthorizedRequest(DbBackend dataStore, int timestamp) async {
    final watchMessage = new Uuid().v4();
    try {
      var replyMap = await dataStore.makeServicePut(
          Uri.parse('/a_la_carte/$watchMessage'),
          {'type': 'authentication_attempt', 'timestamp': timestamp});
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
      DbBackend dataStore, LocalSessionData session, int timestamp) async {
    if (method == 'GET' || method == 'HEAD') {
      return null;
    } else {
      if (session.email == null) {
        return prepareUnauthorizedRequest(dataStore, timestamp);
      }
      List roles = await _retrievePermissions(
          dataStore, session.email, _authorizationDocName);
      if (roles.contains('write') || roles.contains('admin')) {
        return null;
      }
      Map error = {
        'message':
            'You couldn\'t perform this action because you don\'t have the'
            ' correct permissions.',
        'reason': 'Insufficient privileges.',
        'error': 'insufficient_privileges'
      };
      throw new PolicyStateError(error);
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
    Future<Map> _psidState;
    bool psidStateIsSet = false;
    final psidUri = Uri.parse('/a_la_carte/${Uri.encodeComponent(psid)}');
    Future<Map> loadPsidState() async {
      try {
        final psidState = await dbBackend.makeServiceGet(psidUri);
        rev = psidState['_rev'];
        assert(psidState['type'] == 'persistent_session');
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
        await getPsidState();
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

  @override
  Future<Stream<List<int>>> convoluteRequest(
      Map<String, Object> headers,
      Stream<List<int>> requestData,
      LocalSessionData session,
      Map extraData) async {
    final utf8Encoder = new Utf8Encoder();
    final jsonEncoder = new JsonEncoder().fuse(utf8Encoder);
    final nameChunk = utf8Encoder.convert(', "user_data":');
    extraData['user_email'] = session.email;
    extraData['user_full_name'] = session.fullName;
    final dataChunk = jsonEncoder.convert(extraData);

    final bool requestIsChunked = headers['transfer-encoding'] == 'Chunked';
    var contentLength;

    _innerConvolute() async* {
      var previousChunk = [];
      await for (List<int> chunk in requestData) {
        if (requestIsChunked && chunk.length == 0) {
          break;
        } else if (!requestIsChunked && contentLength != null) {
          contentLength -= chunk.length;
          if (contentLength <= 0) {
            previousChunk.addAll(chunk);
            break;
          }
        } else if (!requestIsChunked) {
          break;
        } else if (chunk.any(_isNonWhiteSpace)) {
          if (previousChunk.length != 0) {
            yield previousChunk;
          }
          previousChunk = new List.from(chunk);
        } else {
          previousChunk.addAll(chunk);
        }
      }
      if (contentLength == null && !requestIsChunked) return;
      var indexOfClosingBracket = previousChunk.lastIndexOf(125);
      previousChunk
        ..insertAll(indexOfClosingBracket, dataChunk)
        ..insertAll(indexOfClosingBracket, nameChunk);
      yield previousChunk;
    }

    if (!requestIsChunked && headers.containsKey('content-length')) {
      contentLength = int.parse(headers['content-length']);
    }
    if (!requestIsChunked && contentLength != null) {
      headers['content-length'] =
          (contentLength + nameChunk.length + dataChunk.length).toString();
    }
    return _innerConvolute();
  }

  _isNonWhiteSpace(int ch) {
    switch (ch) {
      case 9:
      case 10:
      case 13:
      case 32:
        return false;
      default:
        return true;
    }
  }

  @override
  Future doOccassionalCleanup(DbBackend backend) async {
    var timestamp = new DateTime.now().millisecondsSinceEpoch;
    var latestAuthenticationAttempt = timestamp - 45 * 60 * 1000;
    try {
      var authenticationAttemptsToDelete = await backend.makeServiceGet(Uri.parse(
          '/a_la_carte/_design/authentication_attempts/_view/all_by_timestamp'
          '?startkey=null&endkey=$latestAuthenticationAttempt'
          '&include_docs=true'));
      for (var row in authenticationAttemptsToDelete['rows']) {
        await backend.makeServiceDelete(
            Uri.parse('/a_la_carte/${row["id"]}'), row['doc']['_rev']);
      }
      var persistentSessionsToDelete = await backend.makeServiceGet(Uri.parse(
          '/a_la_carte/_design/persistent_sessions/_view/all_by_expiration'
          '?startkey=null&endkey=$timestamp'
          '&include_docs=true'));
      for (var row in persistentSessionsToDelete['rows']) {
        await backend.makeServiceDelete(
            Uri.parse('/a_la_carte/${row["id"]}'), row['doc']['_rev']);
      }
    } catch (error) {
      defaultLogger(error.toString(), priority: LoggerPriority.error);
    }
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
