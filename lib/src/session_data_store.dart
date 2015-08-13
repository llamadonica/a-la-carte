// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

part of a_la_carte.server;

class SessionDataStore {
  final String uuid;
  final Set<SendPort> sendPorts;
  DateTime expires;
  DateTime lastRefreshed;
  Timer removeTimer;
  
  SessionDataStore(String this.uuid, DateTime this.expires)
      : sendPorts = new HashSet<SendPort>();
}

