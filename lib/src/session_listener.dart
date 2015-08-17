part of a_la_carte.server;

class _SessionListener {
  final Map<String, SessionDataStore> sessions;
  final Set<String> recentlyExpiredSessions;

  final SendPort sessionMaster;
  final int sessionIdNumber;
  
  SendPort myPort;

  _SessionListener(SendPort this.sessionMaster, int this.sessionIdNumber)
      : sessions = new Map<String, SessionDataStore>(),
        recentlyExpiredSessions = new Set<String>();
  void handleRequests(List data) {
    var requestCode = data[0] as String;
    switch (requestCode) {
      case 'touchCookie':
        _touchCookie(data[1], data[2]);
        break;
      case 'checkOutCookie':
        _checkOutCookie(data[1], data[2]);
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

  void _confirmedSessionDropped(String uuid) {
    recentlyExpiredSessions.add(uuid);
  }
  
  void listen() {
    print('${new DateTime.now()}\tSession handler $sessionIdNumber is up.');
    var receivePort = new ReceivePort();
    myPort = receivePort.sendPort;
    sessionMaster.send(['createdSessionDelegate', myPort]);
    receivePort.listen(handleRequests);
  }

  void _touchCookie(String uuid, SendPort responsePort) {
    if (sessions[uuid] == null) {
      responsePort.send(['invalid']);
      return;
    }
    responsePort.send(['valid']);
    return;
  }

  void _checkOutCookie(String uuid, SendPort responsePort) {
    var session = sessions[uuid];
    if (session == null) {
      responsePort.send(['invalid']);
      return;
    }
    responsePort.send([
      'sessionCheckedOut',
      session.uuid,
      session.expires.millisecondsSinceEpoch,
      session.lastRefreshed.millisecondsSinceEpoch
    ]);
    session.sendPorts.add(responsePort);
    return;
  }
  
  void _checkInCookie(String uuid, SendPort responsePort) {
    var session = sessions[uuid];
    if (session != null) {
      session.sendPorts.remove(responsePort);
    }
  }
  
  void _dropCookie(String uuid) {
    sessions.remove(uuid);
    recentlyExpiredSessions.add(uuid);
    sessionMaster.send(['sessionDropped', uuid, myPort]);
  }
}
