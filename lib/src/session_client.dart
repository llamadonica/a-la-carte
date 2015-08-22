part of a_la_carte.server;

class SessionClient {
  final SendPort _sessionMasterSendPort;
  final ReceivePort _sessionMessagePort = new ReceivePort();
  static const int _expirationDelay = 15000;
  Map<String, LocalSessionData> sessions = new Map<String, LocalSessionData>();

  Map<String, Future> _pendingSessions = new Map<String, Future>();

  SessionClient(SendPort this._sessionMasterSendPort) {
    _sessionMessagePort.listen(_handleSessionClientRequest);
  }

  void _handleSessionClientRequest(data) {
    var requestCode = data[0] as String;
    switch (requestCode) {
      case 'sessionExpired':
        onSessionExpired(data[1]);
        break;
      case 'sessionUpdated':
        _sessionUpdated(data[1], data[2], data[3], data[4], data[5], data[6],
            data[7], data[8], data[9]);
        break;
      case 'sessionUnlockedWithNoUpdates':

      default:
        throw new StateError(
            'Received an invalid reply to a session request: $requestCode.');
    }
  }

  void onSessionExpired(String tsid) {
    sessions.remove(tsid);
  }

  Future<List> _getOrCreateSessionListener(
      String tsid, int currentTimeInMillisecondsSinceEpoch, String psid) async {
    //_defaultLogger('$tsid: Looking up session $tsid.', false);
    final ReceivePort response = new ReceivePort();
    _sessionMasterSendPort
        .send(['getSessionDelegateByTsidOrCreateNew', tsid, response.sendPort]);
    var data = await response.first;
    if (data[1]) {
      final ReceivePort secondaryResponse = new ReceivePort();
      //_defaultLogger('$tsid: Session $tsid. Creating.', false);
      if (psid == null) {
        psid = new Uuid().v1();
      }
      data[0].send([
        'addNewCookie',
        tsid,
        _expirationDelay + currentTimeInMillisecondsSinceEpoch,
        currentTimeInMillisecondsSinceEpoch,
        secondaryResponse.sendPort,
        _sessionMessagePort.sendPort,
        psid
      ]);

      final thisSessionRow = new LocalSessionData(tsid,
          new DateTime.fromMillisecondsSinceEpoch(
              _expirationDelay + currentTimeInMillisecondsSinceEpoch),
          currentTimeInMillisecondsSinceEpoch, data[0], psid);
      sessions[tsid] = thisSessionRow;
      await secondaryResponse.first;
      return [thisSessionRow, data[0]];
    }
    //_defaultLogger('$tsid: Found $tsid. Caching.', false);
    final ReceivePort innerResponse = new ReceivePort();
    data[0].send([
      'checkOutCookie',
      tsid,
      innerResponse.sendPort,
      _sessionMessagePort.sendPort
    ]);
    var sessionParameters = await innerResponse.first;
    //_defaultLogger('Checked out $tsid.', false);
    final thisSessionRow = new LocalSessionData(sessionParameters[0] as String,
        new DateTime.fromMillisecondsSinceEpoch(sessionParameters[2] as int),
        sessionParameters[3] as int, data[0], sessionParameters[1] as String);
    sessions[tsid] = thisSessionRow;
    return [
      thisSessionRow
        ..email = sessionParameters[4]
        ..fullName = sessionParameters[5]
        ..picture = sessionParameters[6],
      data[0]
    ];
  }

  Future<LocalSessionData> getSessionContainer(
      String tsid, int millisecondsSinceEpoch, [String psid = null]) async {
    final session = sessions[tsid];
    if (session != null) {
      touchSession(session, millisecondsSinceEpoch);
      return session;
    } else if (_pendingSessions[tsid] == null) {
      _pendingSessions[tsid] = _getOrCreateSessionListener(
          tsid, new DateTime.now().millisecondsSinceEpoch, psid);
      _pendingSessions[tsid].then((data) {
        sessions[tsid] = data[0];
      });
    }
    return (await _pendingSessions[tsid])[0];
  }

  Future touchSession(
      LocalSessionData session, int millisecondsSinceEpoch) async {
    final ReceivePort reply = new ReceivePort();
    session.master.send(
        ['touchCookie', session.tsid, millisecondsSinceEpoch, reply.sendPort]);
    return reply.first;
  }

  Future<bool> lockSessionForPassiveAuthentication(
      LocalSessionData session, int millisecondsSinceEpoch) async {
    final ReceivePort reply = new ReceivePort();
    session.master.send([
      'lockSessionForPassiveAuthentication',
      session.tsid,
      reply.sendPort,
      _sessionMessagePort.sendPort
    ]);
    return reply.first;
  }

  Future pushClientAuthorizationToMasterAfterPassiveAuthentication(String tsid,
      int currentTimeInMillisecondsSinceEpoch, String psid,
      PolicyIdentity identity, {bool isPassivePush: false}) async {
    _defaultLogger('$tsid: received authorization.', false);
    var data = await _getOrCreateSessionListener(
        tsid, currentTimeInMillisecondsSinceEpoch, psid);
    if (sessions[tsid].lastSeenTime >
        currentTimeInMillisecondsSinceEpoch) return;
    sessions[tsid]
      ..psid = psid
      ..serviceAccount = identity.serviceAccount
      ..email = identity.email
      ..fullName = identity.fullName
      ..picture = identity.picture
      ..shouldPush = isPassivePush;
    data[1].send([
      'authenticatedSessionPassively',
      tsid,
      psid,
      currentTimeInMillisecondsSinceEpoch,
      identity.serviceAccount,
      identity.email,
      identity.fullName,
      identity.picture,
      isPassivePush
    ]);
  }

  void _sessionUpdated(String tsid, int currentTimeInMillisecondsSinceEpoch,
      int expirationTimeInMillisecondsSinceEpoch, String psid,
      String serviceAccount, String email, String fullName, String picture,
      bool isPusher) {
    if (sessions[tsid].lastSeenTime >
        currentTimeInMillisecondsSinceEpoch) return;
    sessions[tsid]
      ..expires = new DateTime.fromMillisecondsSinceEpoch(
          expirationTimeInMillisecondsSinceEpoch)
      ..psid = psid
      ..serviceAccount = serviceAccount
      ..email = email
      ..fullName = fullName
      ..picture = picture
      ..shouldPush = isPusher;
  }
}

void _defaultLogger(String msg, bool isError) {
  if (isError) {
    print('[ERROR] $msg');
  } else {
    print(msg);
  }
}
