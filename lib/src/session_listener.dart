part of a_la_carte.server;

class _SessionListener {
  final Map<String, GlobalSessionData> sessions;
  final Set<String> recentlyExpiredSessions;

  final SendPort sessionMaster;
  final int sessionIdNumber;

  SendPort myPort;

  _SessionListener(SendPort this.sessionMaster, int this.sessionIdNumber)
      : sessions = new Map<String, GlobalSessionData>(),
        recentlyExpiredSessions = new Set<String>();
  void handleRequests(List data) {
    var requestCode = data[0] as String;
    switch (requestCode) {
      case 'addNewCookie':
        _addNewCookie(data[1], data[2], data[3], data[4], data[5], data[6]);
        break;
      case 'touchCookie':
        _touchedSession(data[1], data[2]);
        break;
      case 'checkOutCookie':
        _checkedOutSession(data[1], data[2], data[3]);
        break;
      case 'confirmedSessionDropped':
        _sessionWasDropped(data[1]);
        break;
      case 'authenticatedSession':
        _sessionWasAuthenticated(data[1], data[2], data[3], data[4], data[5],
            data[6], data[7], data[8]);
        break;
      default:
        throw new StateError(
            'Received an invalid reply to a session request: $requestCode.');
    }
  }

  void _sessionWasAuthenticated(String tsid, String psid,
      int currentTimeInMillisecondsSinceEpoch, String serviceAccount,
      String email, String fullName, String picture, bool isPassivePush) {
    final localSession = sessions[tsid];
    if (localSession.lastRefreshed.millisecondsSinceEpoch >
        currentTimeInMillisecondsSinceEpoch) return;
    localSession
      ..psid = psid
      ..serviceAccount = serviceAccount
      ..email = email
      ..fullName = fullName
      ..picture = picture;
    for (var sessionClient in localSession.sendPorts) {
      sessionClient.send([
        'sessionUpdated',
        tsid,
        currentTimeInMillisecondsSinceEpoch,
        localSession.expires.millisecondsSinceEpoch,
        localSession.psid,
        localSession.serviceAccount,
        localSession.email,
        localSession.fullName,
        localSession.picture,
        isPassivePush
      ]);
    }
  }

  void _sessionWasDropped(String tsid) {
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
      int currentTimeInMillisecondsSinceEpoch, SendPort initialResponsePort,
      SendPort responsePort, String psid) {
    _defaultLogger('$tsid: Created a new session $tsid as part of persistent session $psid', false);
    if (sessions.containsKey(tsid)) {
      initialResponsePort.send(null);
      return;
    }
    var session = new GlobalSessionData(tsid,
        new DateTime.fromMillisecondsSinceEpoch(
            expirationTimeInMillisecondsSinceEpoch),
        new DateTime.fromMillisecondsSinceEpoch(
            currentTimeInMillisecondsSinceEpoch), this, psid)
      ..sendPorts.add(responsePort);
    initialResponsePort.send([
      tsid,
      expirationTimeInMillisecondsSinceEpoch,
      currentTimeInMillisecondsSinceEpoch
    ]);
    sessions[tsid] = session;
    sessionMaster.send(['sessionAdded', tsid, myPort]);
  }

  void _touchedSession(String tsid, int currentTimeInMillisecondsSinceEpoch) {
    final session = sessions[tsid];
    if (session == null) {
      return;
    }
    if (currentTimeInMillisecondsSinceEpoch -
            session.lastRefreshed.millisecondsSinceEpoch >
        session.expires.millisecondsSinceEpoch -
            currentTimeInMillisecondsSinceEpoch) {
      final lastExpiration = session.lastRefreshed;
      session.lastRefreshed = new DateTime.fromMillisecondsSinceEpoch(
          currentTimeInMillisecondsSinceEpoch);
      session.expires = new DateTime.fromMillisecondsSinceEpoch(
          session.expires.millisecondsSinceEpoch -
              lastExpiration.millisecondsSinceEpoch +
              currentTimeInMillisecondsSinceEpoch);
      for (var sendPort in session.sendPorts) {
        sendPort.send([
          'sessionUpdated',
          tsid,
          currentTimeInMillisecondsSinceEpoch,
          session.expires.millisecondsSinceEpoch,
          session.psid,
          session.serviceAccount,
          session.email,
          session.fullName,
          session.picture,
          false
        ]);
      }
    }
    return;
  }

  void _checkedOutSession(
      String tsid, SendPort initialResponsePort, SendPort responsePort) {
    var session = sessions[tsid];
    if (session == null) {
      initialResponsePort.send(null);
      return;
    }
    initialResponsePort.send([
      session.tsid,
      session.psid,
      session.expires.millisecondsSinceEpoch,
      session.lastRefreshed.millisecondsSinceEpoch,
      session.email,
      session.fullName,
      session.picture
    ]);
    session.sendPorts.add(responsePort);
    return;
  }

  void dropCookie(String tsid) {
    sessions.remove(tsid);
    recentlyExpiredSessions.add(tsid);
    sessionMaster.send(['sessionDropped', tsid, myPort]);
  }
}
