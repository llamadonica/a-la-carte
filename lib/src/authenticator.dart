library a_la_carte.server.policy_validator;

import 'dart:async';
import 'dart:io';

import 'db_backend.dart';
import 'local_session_data.dart';

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

abstract class AuthenticatorIdentity {
  String get id;
  String get serviceAccount;
  String get email;
  String get fullName;
  String get picture;
}

abstract class Authenticator extends Object {
  Future validateMethodIsPermittedOnResource(String method, Uri uri,
      DbBackend dataStore, LocalSessionData session, int timestamp);
  Future prepareUnauthorizedRequest(DbBackend dataStore, int timestamp);
  Future<Stream<List<int>>> convoluteRequest(Map<String, Object> headers,
      Stream<List<int>> requestData, LocalSessionData session, Map extraData);

  Future<AuthenticatorIdentity> createEmptyPolicyIdentity(
      String psid, String serviceAccount);
  Future<AuthenticatorIdentity> createPolicyIdentityFromState(
      LocalSessionData session,
      String serviceAccount,
      DbBackend dbBackend,
      int currentTimeInMillisecondsSinceEpoch,
      {String code: null,
      String notifyOnAuth: null,
      bool alsoCheckPassivePath: true});
  Future doOccassionalCleanup(DbBackend dbBackend);
}
