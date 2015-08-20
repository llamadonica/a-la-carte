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

  Future<SendPort> _getOrCreateSessionListener(
      String tsid, int currentTimeInMillisecondsSinceEpoch, String psid) {
    final ReceivePort response = new ReceivePort();
    _sessionMasterSendPort
        .send(['getSessionDelegateByTsidOrCreateNew', tsid, response.sendPort]);
    return response.first.then((data) {
      if (data[1]) {
        data[0].send([
          'addNewCookie',
          tsid,
          _expirationDelay + currentTimeInMillisecondsSinceEpoch,
          currentTimeInMillisecondsSinceEpoch,
          response.sendPort,
          _sessionMessagePort.sendPort,
          psid
        ]);
        return new SessionClientRow(tsid,
            new DateTime.fromMillisecondsSinceEpoch(
                _expirationDelay + currentTimeInMillisecondsSinceEpoch),
            currentTimeInMillisecondsSinceEpoch, psid);
      }
      final ReceivePort innerResponse = new ReceivePort();
      data[0].send([
        'checkOutCookie',
        tsid,
        innerResponse.sendPort,
        _sessionMessagePort.sendPort
      ]);
      return innerResponse.first.then((data) => new SessionClientRow(
          data[0], new DateTime.fromMillisecondsSinceEpoch(data[2]), data[3], data[1]));
    });
  }

  Future<SessionClientRow> getSessionContainer(String tsid,
      [String psid = null]) async {
    if (sessions[tsid] != null) {
      return sessions[tsid];
    } else if (_pendingSessions[tsid] == null) {
      _pendingSessions[tsid] = _getOrCreateSessionListener(
          tsid, new DateTime.now().millisecondsSinceEpoch, psid);
    }
    return await _pendingSessions[tsid];
  }

  Future pushClientAuthorizationToListener(String tsid,
      int currentTimeInMillisecondsSinceEpoch, String psid,
      PolicyIdentity identity, {bool isPassivePush: false}) async {
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

  void _sessionUpdated(String tsid, String psid,
      int currentTimeInMillisecondsSinceEpoch, int expirationTimeInMillisecondsSinceEpoch, String serviceAccount,
      String email, String fullName, String picture, bool isPusher) {
    if (sessions[tsid].lastSeenTime >
        currentTimeInMillisecondsSinceEpoch) return;
    sessions[tsid]
      ..expires = new DateTime.fromMillisecondsSinceEpoch(expirationTimeInMillisecondsSinceEpoch)
      ..psid = psid
      ..serviceAccount = serviceAccount
      ..email = email
      ..fullName = fullName
      ..picture = picture;
  }
}
