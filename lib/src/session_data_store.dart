// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

part of a_la_carte.server;

class GlobalSessionData {
  final String tsid;
  final _SessionListener _parent;

  bool isLockedForPassiveAuthentication = false;
  bool isAuthenticated = null;

  String psid;
  String identifier;

  final Set<SendPort> sendPorts = new HashSet<SendPort>();

  final Set<SendPort> sendPortsToBeNotifiedOnPassiveUnlock =
      new HashSet<SendPort>();
  final Set<SendPort> sendPortsThatAreDeactivatedUntilPassiveUnlock =
      new HashSet<SendPort>();

  DateTime _expires;
  String serviceAccount;
  String email;
  String fullName;
  String picture;

  DateTime get expires => _expires;
  void set expires(DateTime value) {
    _expires = value;
    updateExpirationTimer();
  }

  DateTime lastRefreshed;
  Timer removeTimer;

  GlobalSessionData(String this.tsid, DateTime this._expires,
      DateTime this.lastRefreshed, _SessionListener this._parent,
      [String this.psid = null, String this.identifier = null]) {
    updateExpirationTimer();
  }

  void updateExpirationTimer() {
    if (removeTimer != null) {
      removeTimer.cancel();
    }
    removeTimer = new Timer(_expires.difference(lastRefreshed), _expireSession);
  }

  void _expireSession() {
    for (var sendPort in sendPorts) {
      sendPort.send(['sessionExpired', tsid]);
    }
    _parent.dropCookie(tsid);
  }
}

class LocalSessionData {
  final String tsid;
  String serviceAccount;
  String psid;
  String fullName;
  String email;
  String picture;
  bool shouldPush = false;
  int lastSeenTime;
  final SendPort master;

  DateTime expires;
  LocalSessionData(String this.tsid, DateTime this.expires,
      int this.lastSeenTime, SendPort this.master, [String this.psid = null]);
}
