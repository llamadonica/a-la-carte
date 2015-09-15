// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
library a_la_carte.server.global_session_data;

import 'dart:isolate';
import 'dart:async';
import 'dart:collection';

class GlobalSessionData {
  final String tsid;

  bool isLockedForPassiveAuthentication = false;
  bool isLockedForActiveAuthentication = false;
  bool isAuthenticatedPassively = null;
  bool isAuthenticatedActively = null;
  SendPort waitingToStepFromPassiveToActive;

  String psid;
  String identifier;

  final Set<SendPort> sendPorts = new HashSet<SendPort>();

  Set<SendPort> sendPortsToBeNotifiedOnPassiveUnlock = new HashSet<SendPort>();
  Set<SendPort> sendPortsThatAreDeactivatedUntilPassiveUnlock =
      new HashSet<SendPort>();
  Set<SendPort> sendPortsToBeNotifiedOnActiveUnlock = new HashSet<SendPort>();
  Set<SendPort> sendPortsThatAreDeactivatedUntilActiveUnlock =
      new HashSet<SendPort>();

  DateTime _expires;
  Function _expireSession;
  String serviceAccount;
  String email;
  String fullName;
  String picture;

  DateTime get expires => _expires;
  void set expires(DateTime value) {
    _expires = value;
    _updateExpirationTimer();
  }

  Function get expireSession => _expireSession;
  void set expireSession(Function value) {
    _expireSession = value;
    _updateExpirationTimer();
  }

  DateTime lastRefreshed;
  Timer removeTimer;

  GlobalSessionData(
      String this.tsid, DateTime this._expires, DateTime this.lastRefreshed,
      [String this.psid = null, String this.identifier = null]);

  void _updateExpirationTimer() {
    if (removeTimer != null) {
      removeTimer.cancel();
    }
    if (_expires != null && _expireSession != null) {
      removeTimer =
          new Timer(_expires.difference(lastRefreshed), expireSession);
    }
  }
}
