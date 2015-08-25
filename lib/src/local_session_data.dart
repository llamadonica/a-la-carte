// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.
library a_la_carte.server.local_session_data;
import 'dart:isolate';

class LocalSessionData {
  final String tsid;
  final SendPort master;

  String serviceAccount;
  String psid;
  String fullName;
  String email;
  String picture;
  int refCount = 0;
  bool mustRecertify = false;
  bool isAuthenticated = false;
  int lastSeenTime;

  DateTime expires;
  LocalSessionData(String this.tsid, DateTime this.expires,
                   int this.lastSeenTime, SendPort this.master,
                   [String this.psid = null]);
}
