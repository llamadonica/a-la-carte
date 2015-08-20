part of a_la_carte.server;

class SessionClient {
  final SendPort _sessionMasterSendPort;
  final ReceivePort _sessionMessagePort = new ReceivePort();
  static const int _expirationDelay = 900000;
  Map<String, SessionClientRow> sessions = new Map<String, SessionClientRow>();
  Map<String, Future> _pendingSessions = new Map<String, Future>();
  Map<String, List<String>> tsidsByPsid = new Map();

  SessionClient(SendPort this._sessionMasterSendPort) {
    _sessionMessagePort.listen(_handleSessionClientRequest);
  }

  void _handleSessionClientRequest(data) {
    var requestCode = data[0] as String;
    switch (requestCode) {
      case 'sessionExpired':
        _sessionExpired(data[1]);
        break;
      case 'sessionUpdated':
        _sessionUpdated(data[1], data[2], data[3], data[4], data[5], data[6],
            data[7], data[8], data[9]);
        break;
      default:
        throw new StateError(
            'Received an invalid reply to a session request: $requestCode.');
    }
  }

  void _sessionExpired(String tsid) {
    sessions.remove(tsid);
  }

  Future<List> _getOrCreateSessionListener(
      String tsid, int currentTimeInMillisecondsSinceEpoch, String psid) async {
    _defaultLogger('$tsid: Looking up session $tsid.', false);
    final ReceivePort response = new ReceivePort();
    _sessionMasterSendPort
        .send(['getSessionDelegateByTsidOrCreateNew', tsid, response.sendPort]);
    var data = await response.first;
    if (data[1]) {
      _defaultLogger('$tsid: Session $tsid. Creating.', false);
      if (psid == null) {
        psid = new Uuid().v1();
      }
      data[0].send([
        'addNewCookie',
        tsid,
        _expirationDelay + currentTimeInMillisecondsSinceEpoch,
        currentTimeInMillisecondsSinceEpoch,
        response.sendPort,
        _sessionMessagePort.sendPort,
        psid
      ]);
      return [
        new SessionClientRow(
            tsid,
            new DateTime.fromMillisecondsSinceEpoch(
                _expirationDelay + currentTimeInMillisecondsSinceEpoch),
            currentTimeInMillisecondsSinceEpoch,
            psid),
        data
      ];
    }
    _defaultLogger('$tsid: Found $tsid. Caching.', false);
    final ReceivePort innerResponse = new ReceivePort();
    data[0].send([
      'checkOutCookie',
      tsid,
      innerResponse.sendPort,
      _sessionMessagePort.sendPort
    ]);
    var sessionParameters = await innerResponse.first;
    _defaultLogger('Checked out $tsid.', false);
    return [
      new SessionClientRow(
          sessionParameters[0] as String,
          new DateTime.fromMillisecondsSinceEpoch(sessionParameters[2] as int),
          sessionParameters[3] as int,
          sessionParameters[1] as String)
        ..email = sessionParameters[4]
        ..fullName = sessionParameters[5]
        ..picture = sessionParameters[6],
      data
    ];
  }

  Future<SessionClientRow> getSessionContainer(String tsid,
      [String psid = null]) async {
    if (sessions[tsid] != null) {
      return sessions[tsid];
    } else if (_pendingSessions[tsid] == null) {
      _pendingSessions[tsid] = _getOrCreateSessionListener(
          tsid, new DateTime.now().millisecondsSinceEpoch, psid);
      _pendingSessions[tsid].then((data) {
        sessions[tsid] = data[0];
      });
    }
    return (await _pendingSessions[tsid])[0];
  }

  Future pushClientAuthorizationToListener(
      String tsid,
      int currentTimeInMillisecondsSinceEpoch,
      String psid,
      PolicyIdentity identity,
      {bool isPassivePush: false}) async {
    _defaultLogger('$tsid received authorization.', false);
    var data = await _getOrCreateSessionListener(
        tsid, currentTimeInMillisecondsSinceEpoch, psid);
    if (sessions[tsid].lastSeenTime >
        currentTimeInMillisecondsSinceEpoch) return;
    sessions[tsid]
      ..psid = psid
      ..serviceAccount = identity.serviceAccount
      ..email = identity.email
      ..fullName = identity.fullName
      ..picture = identity.picture;
    data[0].send([
      'authenticatedSession',
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

  void _sessionUpdated(
      String tsid,
      String psid,
      int currentTimeInMillisecondsSinceEpoch,
      int expirationTimeInMillisecondsSinceEpoch,
      String serviceAccount,
      String email,
      String fullName,
      String picture,
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
      ..picture = picture;
  }
}

void _defaultLogger(String msg, bool isError) {
  if (isError) {
    print('[ERROR] $msg');
  } else {
    print(msg);
  }
}
