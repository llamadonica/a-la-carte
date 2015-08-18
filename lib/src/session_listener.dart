part of a_la_carte.server;

class _SessionListener {
  final Map<String, SessionListenerRow> sessions;
  final Set<String> recentlyExpiredSessions;

  final SendPort sessionMaster;
  final int sessionIdNumber;

  SendPort myPort;

  _SessionListener(SendPort this.sessionMaster, int this.sessionIdNumber)
      : sessions = new Map<String, SessionListenerRow>(),
        recentlyExpiredSessions = new Set<String>();
  void handleRequests(List data) {
    var requestCode = data[0] as String;
    switch (requestCode) {
      case 'addNewCookie':
        _addNewCookie(data[1], data[2], data[3], data[4], data[5]);
        break;
      case 'touchCookie':
        _touchCookie(data[1], data[2]);
        break;
      case 'checkOutCookie':
        _checkOutCookie(data[1], data[2], data[3]);
        break;
      case 'checkInCookie':
        _checkInCookie(data[1], data[2]);
        break;
      case 'confirmedSessionDropped':
        _confirmedSessionDropped(data[1]);
        break;
      default:
        throw new StateError(
            'Received an invalid reply to a session request: $requestCode.');
    }
  }

  void _confirmedSessionDropped(String tsid) {
    recentlyExpiredSessions.remove(tsid);
  }

  void listen() {
    print('${new DateTime.now()}\tSession handler $sessionIdNumber is up.');
    var receivePort = new ReceivePort();
    myPort = receivePort.sendPort;
    sessionMaster.send(['createdSessionDelegate', myPort]);
    receivePort.listen(handleRequests);
  }

  void _addNewCookie(String tsid, int expirationTimeInMillisecondsSinceEpoch,
      int currentTimeInMillisecondsSinceEpoch, SendPort initialResponsePort, SendPort responsePort) {
    if (sessions.containsKey(tsid)) {
      initialResponsePort.send(null);
      return;
    }
    var session = new SessionListenerRow(tsid,
        new DateTime.fromMillisecondsSinceEpoch(
            expirationTimeInMillisecondsSinceEpoch),
        new DateTime.fromMillisecondsSinceEpoch(
            currentTimeInMillisecondsSinceEpoch), this)
      ..sendPorts.add(responsePort);
    initialResponsePort.send([
      tsid,
      expirationTimeInMillisecondsSinceEpoch,
      currentTimeInMillisecondsSinceEpoch
    ]);
    sessions[tsid] = session;
    sessionMaster.send(['sessionAdded', tsid, myPort]);
  }

  void _touchCookie(String tsid, int currentTimeInMillisecondsSinceEpoch) {
    final session = sessions[tsid];
    if (session == null) {
      return;
    }
    if (currentTimeInMillisecondsSinceEpoch -
            session.lastRefreshed.millisecondsSinceEpoch >
        session.expires.millisecondsSinceEpoch -
            currentTimeInMillisecondsSinceEpoch) {
      final lastExpiration = session.lastRefreshed;
      session.lastRefreshed = new DateTime.fromMillisecondsSinceEpoch(currentTimeInMillisecondsSinceEpoch);
      session.expires = new DateTime.fromMillisecondsSinceEpoch(session.expires.millisecondsSinceEpoch - lastExpiration.millisecondsSinceEpoch + currentTimeInMillisecondsSinceEpoch);
      for (var sendPort in session.sendPorts) {
        sendPort.send(['sessionUpdated', tsid, currentTimeInMillisecondsSinceEpoch, session.expires.millisecondsSinceEpoch]);
      }
    }
    return;
  }

  void _checkOutCookie(String tsid, SendPort initialResponsePort, SendPort responsePort) {
    var session = sessions[tsid];
    if (session == null) {
      initialResponsePort.send(null);
      return;
    }
    initialResponsePort.send([
      session.tsid,
      session.expires.millisecondsSinceEpoch,
      session.lastRefreshed.millisecondsSinceEpoch
    ]);
    session.sendPorts.add(responsePort);
    return;
  }

  void _checkInCookie(String tsid, SendPort responsePort) {
    var session = sessions[tsid];
    if (session != null) {
      session.sendPorts.remove(responsePort);
    }
  }

  void dropCookie(String tsid) {
    sessions.remove(tsid);
    recentlyExpiredSessions.add(tsid);
    sessionMaster.send(['sessionDropped', tsid, myPort]);
  }
}
