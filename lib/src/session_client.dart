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

  Future _createOrCheckoutNewSession(
      String tsid, int currentTimeInMillisecondsSinceEpoch, String psid) async {
    final ReceivePort response = new ReceivePort();
    final Completer<SessionClientRow> completer =
        new Completer<SessionClientRow>();
    response.listen((data) {
      if (data == null) {
        completer.completeError(
            new StateError("Could not understand response to create session"));
      } else {
        completer.complete(_sessionCheckedOut(data[0], data[1], data[2]));
      }
    });
    var sessionListener = await _getOrCreateSessionListener(tsid);
    if (sessionListener == null) {
      sessionListener = await _bestSessionListener(tsid);
      sessionListener.send([
        'addNewCookie',
        tsid,
        _expirationDelay + currentTimeInMillisecondsSinceEpoch,
        currentTimeInMillisecondsSinceEpoch,
        response.sendPort,
        _sessionMessagePort.sendPort
      ]);
    } else {
      sessionListener.send([
        'checkOutCookie',
        tsid,
        response.sendPort,
        _sessionMessagePort.sendPort
      ]);
      sessionListener
          .send(['touchCookie', tsid, currentTimeInMillisecondsSinceEpoch]);
    }
  }

  Future<SendPort> _getOrCreateSessionListener(
      String tsid, int currentTimeInMillisecondsSinceEpoch) {
    final ReceivePort response = new ReceivePort();
    final Completer<SendPort> completer = new Completer<SendPort>();
    response.listen((data) {
      if (data[1]) {
        data[0].send([
          'addNewCookie',
          tsid,
          _expirationDelay + currentTimeInMillisecondsSinceEpoch,
          currentTimeInMillisecondsSinceEpoch,
          response.sendPort,
          _sessionMessagePort.sendPort
        ]);
      }
      completer.complete(data[0]);
    });
    _sessionMasterSendPort
        .send(['getSessionDelegateByTsidOrCreateNew', tsid, response.sendPort]);
    return completer.future;
  }

  Future<SessionClientRow> getSessionContainer(String tsid,
      [String psid = null]) {
    if (sessions[tsid] != null) {
      return new Future.value(sessions[tsid]);
    } else if (_pendingSessions[tsid] == null) {
      _pendingSessions[tsid] = _createOrCheckoutNewSession(
          tsid, new DateTime.now().millisecondsSinceEpoch, psid);
    }
    return _pendingSessions[tsid];
  }

  SessionClientRow _sessionCheckedOut(
      String tsid,
      int expiresMillisecondsSinceEpoch,
      int lastRefreshedMillisecondsSinceEpoch) {
    final clientSession = new SessionClientRow(tsid,
        new DateTime.fromMillisecondsSinceEpoch(expiresMillisecondsSinceEpoch));
    sessions[tsid] = clientSession;
    return clientSession;
  }
}
