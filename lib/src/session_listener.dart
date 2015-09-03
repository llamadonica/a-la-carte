library a_la_carte.server.session_listener;

import 'dart:isolate';
import 'dart:collection';

import 'logger.dart';
import 'global_session_data.dart';

class SessionListener {
  final Logger _defaultLogger;
  final Map<String, GlobalSessionData> _sessions;
  final Set<String> _recentlyExpiredSessions;
  final Map<String, List<SendPort>> _waitingInitialReplyPorts = new Map();
  final Map<String, List<SendPort>> _waitingReplyPorts = new Map();
  final SendPort sessionMaster;
  final int sessionIdNumber;

  SendPort myPort;

  SessionListener(SendPort this.sessionMaster, int this.sessionIdNumber, Logger this._defaultLogger)
      : _sessions = new Map<String, GlobalSessionData>(),
        _recentlyExpiredSessions = new Set<String>();

  void handleRequests(List data) {
    var requestCode = data[0] as String;
    switch (requestCode) {
      case 'addNewCookie':
        _addNewCookie(data[1], data[2], data[3], data[4], data[5], data[6]);
        break;
      case 'touchCookie':
        _touchedSession(data[1], data[2], data[3]);
        break;
      case 'checkOutCookie':
        _checkedOutSession(data[1], data[2], data[3]);
        break;
      case 'confirmedSessionDropped':
        _sessionWasDropped(data[1]);
        break;
      case 'authenticatedSession':
        _unlockSessionAfterAuthenticationSucceeded(
            data[1], data[2], data[3], data[4], data[5], data[6], data[7]);
        break;
      case 'lockSessionForPassiveAuthentication':
        _lockSessionForPassiveAuthentication(
            data[1] as String, data[2] as SendPort, data[3] as SendPort);
        break;
      case 'lockSessionForActiveAuthentication':
        _lockSessionForActiveAuthentication(
            data[1] as String, data[2] as SendPort, data[3] as SendPort);
        break;
      case 'unlockSessionAfterPassiveAuthenticationFailed':
        _unlockSessionAfterPassiveAuthenticationFailed(data[1] as String);
        break;
      case 'unlockSessionAfterActiveAuthenticationFailed':
        _unlockSessionAfterActiveAuthenticationFailed(data[1] as String);
        break;
      default:
        throw new StateError(
            'Received an invalid reply to a session request: $requestCode.');
    }
  }

  void _lockSessionForActiveAuthentication(
      String tsid, SendPort sendPort, SendPort originalSendPort) {
    final localSession = _sessions[tsid];
    if (localSession.isLockedForPassiveAuthentication) {
      localSession.waitingToStepFromPassiveToActive = originalSendPort;
      localSession.sendPortsThatAreDeactivatedUntilPassiveUnlock
          .add(originalSendPort);
      localSession.sendPorts.remove(originalSendPort);
      localSession.isLockedForActiveAuthentication = true;
    } else if (localSession.isAuthenticatedActively == true) {
      sendPort.send([
        false, //No you didn't get to authenticate.
        true, //Yes it did authenticate.
        tsid,
        localSession.lastRefreshed.millisecondsSinceEpoch,
        localSession.expires.millisecondsSinceEpoch,
        localSession.psid,
        localSession.serviceAccount,
        localSession.email,
        localSession.fullName,
        localSession.picture,
        localSession.isAuthenticatedPassively
      ]);
    } else if (localSession.isAuthenticatedActively == false) {
      sendPort.send([false, false]);
    } else if (localSession.isLockedForActiveAuthentication) {
      localSession.sendPortsToBeNotifiedOnActiveUnlock.add(sendPort);
      localSession.sendPortsThatAreDeactivatedUntilActiveUnlock
          .add(originalSendPort);
      localSession.sendPorts.remove(originalSendPort);
    } else {
      localSession.isLockedForActiveAuthentication = true;
      localSession.isLockedForPassiveAuthentication = true;
      sendPort.send([
        true, // Yes, you are the controlling agent
        localSession.isAuthenticatedPassively ==
            null // Whether to do a check on passive authentication first
      ]);
    }
  }

  void _unlockSessionAfterActiveAuthenticationFailed(String tsid) {
    final localSession = _sessions[tsid];
    assert(localSession.isLockedForActiveAuthentication);
    for (var sendPort in localSession.sendPortsToBeNotifiedOnActiveUnlock) {
      sendPort.send([false, false]);
    }
    for (var sendPort in localSession.sendPortsToBeNotifiedOnPassiveUnlock) {
      sendPort.send([false, false]);
    }
    for (var originalSendPort
        in localSession.sendPortsThatAreDeactivatedUntilPassiveUnlock) {
      localSession.sendPorts.add(originalSendPort);
    }
    for (var originalSendPort
        in localSession.sendPortsThatAreDeactivatedUntilActiveUnlock) {
      localSession.sendPorts.add(originalSendPort);
    }
    localSession
      ..isLockedForPassiveAuthentication = false
      ..isAuthenticatedPassively = false
      ..isLockedForActiveAuthentication = false
      ..isAuthenticatedActively = false
      ..sendPortsToBeNotifiedOnPassiveUnlock = new HashSet()
      ..sendPortsThatAreDeactivatedUntilPassiveUnlock = new HashSet()
      ..sendPortsToBeNotifiedOnActiveUnlock = new HashSet()
      ..sendPortsThatAreDeactivatedUntilActiveUnlock = new HashSet();
  }

  void _lockSessionForPassiveAuthentication(
      String tsid, SendPort sendPort, SendPort originalSendPort) {
    final localSession = _sessions[tsid];
    if (localSession.isLockedForPassiveAuthentication ||
        localSession.isLockedForActiveAuthentication) {
      localSession.sendPortsToBeNotifiedOnPassiveUnlock.add(sendPort);
      localSession.sendPortsThatAreDeactivatedUntilPassiveUnlock
          .add(originalSendPort);
      localSession.sendPorts.remove(originalSendPort);
    } else if (localSession.isAuthenticatedPassively == true) {
      sendPort.send([
        false, //No you didn't get to authenticate.
        true, //Yes it did authenticate.
        tsid,
        localSession.lastRefreshed.millisecondsSinceEpoch,
        localSession.expires.millisecondsSinceEpoch,
        localSession.psid,
        localSession.serviceAccount,
        localSession.email,
        localSession.fullName,
        localSession.picture,
        localSession.isAuthenticatedPassively
      ]);
    } else if (localSession.isAuthenticatedPassively == false) {
      sendPort.send([false, false]);
    } else {
      assert(localSession.isAuthenticatedPassively == null);
      localSession.isLockedForPassiveAuthentication = true;
      sendPort.send([true]);
    }
  }

  void _unlockSessionAfterPassiveAuthenticationFailed(String tsid) {
    final localSession = _sessions[tsid];
    assert(localSession.isLockedForPassiveAuthentication);
    if (localSession.waitingToStepFromPassiveToActive != null) {
      localSession.waitingToStepFromPassiveToActive.send([true]);
    }
    if (localSession.waitingToStepFromPassiveToActive != null) {
      localSession.waitingToStepFromPassiveToActive.send([
        true, // Yes, you are the controlling agent
        false // Whether to check passive authentication first.
      ]);
      localSession.waitingToStepFromPassiveToActive = null;
    } else {
      for (var sendPort in localSession.sendPortsToBeNotifiedOnPassiveUnlock) {
        sendPort.send([false, false]);
      }
      for (var originalSendPort
          in localSession.sendPortsThatAreDeactivatedUntilPassiveUnlock) {
        localSession.sendPorts.add(originalSendPort);
      }
    }
    localSession
      ..sendPortsToBeNotifiedOnPassiveUnlock = new HashSet()
      ..sendPortsThatAreDeactivatedUntilPassiveUnlock = new HashSet()
      ..isLockedForPassiveAuthentication = false
      ..isAuthenticatedPassively = false;
  }

  void _unlockSessionAfterAuthenticationSucceeded(
      String tsid,
      String psid,
      int currentTimeInMillisecondsSinceEpoch,
      String serviceAccount,
      String email,
      String fullName,
      String picture) {
    final localSession = _sessions[tsid];
    assert(localSession.isLockedForPassiveAuthentication);
    localSession
      ..psid = psid
      ..serviceAccount = serviceAccount
      ..email = email
      ..fullName = fullName
      ..picture = picture
      ..isAuthenticatedPassively = true;

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
        localSession.isAuthenticatedPassively
      ]);
    }
    if (localSession.waitingToStepFromPassiveToActive != null) {
      localSession.waitingToStepFromPassiveToActive.send([
        false, //No you didn't get to authenticate.
        true, //Yes it did authenticate.
        tsid,
        currentTimeInMillisecondsSinceEpoch,
        localSession.expires.millisecondsSinceEpoch,
        localSession.psid,
        localSession.serviceAccount,
        localSession.email,
        localSession.fullName,
        localSession.picture,
        localSession.isAuthenticatedPassively
      ]);
      localSession.waitingToStepFromPassiveToActive = null;
    }
    for (var sessionClient
        in localSession.sendPortsToBeNotifiedOnPassiveUnlock) {
      sessionClient.send([
        false, //No you didn't get to authenticate.
        true, //Yes it did authenticate.
        tsid,
        currentTimeInMillisecondsSinceEpoch,
        localSession.expires.millisecondsSinceEpoch,
        localSession.psid,
        localSession.serviceAccount,
        localSession.email,
        localSession.fullName,
        localSession.picture,
        localSession.isAuthenticatedPassively
      ]);
    }
    for (var sessionClient
        in localSession.sendPortsToBeNotifiedOnActiveUnlock) {
      sessionClient.send([
        false, //No you didn't get to authenticate.
        true, //Yes it did authenticate.
        tsid,
        currentTimeInMillisecondsSinceEpoch,
        localSession.expires.millisecondsSinceEpoch,
        localSession.psid,
        localSession.serviceAccount,
        localSession.email,
        localSession.fullName,
        localSession.picture,
        localSession.isAuthenticatedPassively
      ]);
    }
    for (var originalSendPort
        in localSession.sendPortsThatAreDeactivatedUntilPassiveUnlock) {
      localSession.sendPorts.add(originalSendPort);
    }
    for (var originalSendPort
        in localSession.sendPortsThatAreDeactivatedUntilActiveUnlock) {
      localSession.sendPorts.add(originalSendPort);
    }
    localSession.sendPortsToBeNotifiedOnPassiveUnlock = new HashSet();
    localSession.sendPortsThatAreDeactivatedUntilPassiveUnlock = new HashSet();
    localSession.sendPortsToBeNotifiedOnActiveUnlock = new HashSet();
    localSession.sendPortsThatAreDeactivatedUntilActiveUnlock = new HashSet();
    localSession.isLockedForPassiveAuthentication = false;
    localSession.isAuthenticatedPassively = true;
    localSession.isAuthenticatedActively = true;
  }

  void _sessionWasDropped(String tsid) {
    _recentlyExpiredSessions.remove(tsid);
  }

  void listen() {
    print('${new DateTime.now()}\tSession handler $sessionIdNumber is up.');
    var receivePort = new ReceivePort();
    myPort = receivePort.sendPort;
    sessionMaster.send(['createdSessionDelegate', myPort]);
    receivePort.listen(handleRequests);
  }

  void _addNewCookie(
      String tsid,
      int expirationTimeInMillisecondsSinceEpoch,
      int currentTimeInMillisecondsSinceEpoch,
      SendPort initialResponsePort,
      SendPort responsePort,
      String psid) {
    _defaultLogger(
        '$tsid: Created a new session $tsid as part of persistent session $psid');
    if (_sessions.containsKey(tsid)) {
      initialResponsePort.send(null);
      return;
    }
    var session = new GlobalSessionData(
        tsid,
        new DateTime.fromMillisecondsSinceEpoch(
            expirationTimeInMillisecondsSinceEpoch),
        new DateTime.fromMillisecondsSinceEpoch(
            currentTimeInMillisecondsSinceEpoch),
        psid);

    session
      ..sendPorts.add(responsePort)
      ..expireSession = () {
      _expireSession(session);
    };

    if (_waitingReplyPorts.containsKey(tsid)) {
      session.sendPorts.addAll(_waitingReplyPorts[tsid]);
      _waitingInitialReplyPorts[tsid]
          .forEach((resposePort) => responsePort.send([
                tsid,
                expirationTimeInMillisecondsSinceEpoch,
                currentTimeInMillisecondsSinceEpoch
              ]));
    }

    initialResponsePort.send([
      tsid,
      expirationTimeInMillisecondsSinceEpoch,
      currentTimeInMillisecondsSinceEpoch
    ]);
    _sessions[tsid] = session;
    sessionMaster.send(['sessionAdded', tsid, myPort]);
  }

  void _expireSession(GlobalSessionData data) {
    for (var sendPort in data.sendPorts) {
      sendPort.send(['sessionExpired', data.tsid]);
    }
    dropCookie(data.tsid);
  }

  void _touchedSession(String tsid, int currentTimeInMillisecondsSinceEpoch,
      SendPort replyPort) {
    final session = _sessions[tsid];
    if (session == null) {
      replyPort.send([]);
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
    replyPort.send([]);
  }

  void _checkedOutSession(
      String tsid, SendPort initialResponsePort, SendPort responsePort) {
    var session = _sessions[tsid];
    if (session == null && !_waitingInitialReplyPorts.containsKey(tsid)) {
      _waitingInitialReplyPorts[tsid] = [];
      _waitingReplyPorts[tsid] = [];
    }
    if (session == null) {
      _waitingInitialReplyPorts[tsid].add(initialResponsePort);
      _waitingReplyPorts[tsid].add(responsePort);
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
    _sessions.remove(tsid);
    _recentlyExpiredSessions.add(tsid);
    sessionMaster.send(['sessionDropped', tsid, myPort]);
  }
}
