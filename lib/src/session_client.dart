part of a_la_carte.server;

class SessionClient {
  final SendPort _sessionMasterSendPort;
  final ReceivePort _sessionMessagePort = new ReceivePort();
  static const int _expirationDelay = 900000;
  Map<String, SessionClientRow> sessions = new Map<String, SessionClientRow>();
  Map<String, Future> _pendingSessions = new Map<String, Future>();

  SessionClient(SendPort this._sessionMasterSendPort) {
    _sessionMessagePort.listen(_handleSessionClientRequest);
  }

  void _handleSessionClientRequest(data) {
    var requestCode = data[0] as String;
    switch (requestCode) {
      case 'sessionExpired':
        _sessionExpired(data[1]);
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
                _expirationDelay + currentTimeInMillisecondsSinceEpoch), psid);
      }
      final ReceivePort innerResponse = new ReceivePort();
      data[0].send([
        'checkOutCookie',
        tsid,
        innerResponse.sendPort,
        _sessionMessagePort.sendPort
      ]);
      return innerResponse.first.then((data) => new SessionClientRow(
          data[0], new DateTime.fromMillisecondsSinceEpoch(data[2]), data[1]));
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
    var sessionListener = await _pendingSessions[tsid];
  }

  SessionClientRow _sessionCheckedOut(String tsid,
      int expiresMillisecondsSinceEpoch,
      int lastRefreshedMillisecondsSinceEpoch) {
    final clientSession = new SessionClientRow(tsid,
        new DateTime.fromMillisecondsSinceEpoch(expiresMillisecondsSinceEpoch));
    sessions[tsid] = clientSession;
    return clientSession;
  }
}
