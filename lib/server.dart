library a_la_carte.server;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:stack_trace/stack_trace.dart' as stack_trace;
import 'package:uuid/uuid.dart';

part 'src/couch_datastore_abstraction.dart';
part 'src/session_data_store.dart';
part 'src/http_listener_isolate.dart';
part 'src/session_listener.dart';
part 'src/session_master.dart';
part 'src/policy_handler.dart';
part 'src/oauth_identity_data_store.dart';

class Server {
  final int port;
  final int couchPort;
  final int listeners;
  
  Server(int this.port, int this.couchPort, int this.listeners);
  void serve() {
    var sessionResponse = new ReceivePort();
    sessionResponse.first.then((SendPort sessionPort) {
      for (var i = 1; i < listeners; i++) {
        Isolate.spawn(_mainListenerIsolate, [port, i, couchPort, sessionPort]);
      }
      var listener = new HttpListenerIsolate(port, 0, couchPort, sessionPort);
      listener.listen();
    });
    Isolate.spawn(_sessionMasterIsolate, [sessionResponse.sendPort]);
  }
}

void _mainListenerIsolate(List args) {
  var listener = new HttpListenerIsolate(
      args[0] as int,
      args[1] as int,
      args[2] as int,
      args[3] as SendPort);
  listener.listen();
}

void _sessionMasterIsolate(List args) {
  var sessionListener = new SessionMaster(1);
  (args[0] as SendPort).send(sessionListener.httpSendPort);
}
