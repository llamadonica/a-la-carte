// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

part of a_la_carte.server;

class SessionListenerRow {
  final String tsid;
  final _SessionListener _parent;
  String psid;
  String id;

  final Set<SendPort> sendPorts = new HashSet<SendPort>();

  DateTime _expires;
  DateTime get expires => _expires;
  void set expires(DateTime value) {
    _expires = value;
    updateExpirationTimer();
  }
  DateTime lastRefreshed;
  Timer removeTimer;

  SessionListenerRow(String this.tsid, DateTime this._expires, DateTime this.lastRefreshed,
                     _SessionListener this._parent,
      [String this.psid = null, String this.id = null]) {
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

class SessionClientRow {
  final String tsid;
  String psid;
  String id;
  DateTime expires;
  SessionClientRow(String this.tsid, DateTime this.expires,
      [String this.psid = null, String this.id = null]);
}
