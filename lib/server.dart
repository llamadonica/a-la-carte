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
import 'package:oauth2/oauth2.dart' as oauth2;

import 'src/couch_db_backend.dart';
import 'src/db_backend.dart';
import 'src/policy_validator.dart';
import 'src/global_session_data.dart';
import 'src/http_listener_isolate.dart';
import 'src/session_client.dart';
import 'src/session_listener.dart';
import 'src/session_master.dart';

class Server {
  final int port;
  final int couchPort;
  final int listeners;
  final bool debugOverWire;

  Server(int this.port, int this.couchPort, int this.listeners,
      {this.debugOverWire: false});
  void serve() {
    var sessionResponse = new ReceivePort();
    sessionResponse.first.then((SendPort sessionPort) {
      for (var i = 1; i < listeners; i++) {
        Isolate.spawn(_mainListenerIsolate, [
          port,
          i,
          couchPort,
          sessionPort,
          debugOverWire
        ]);
      }
      var listener = new HttpListenerIsolateImpl(
          port, 0, sessionPort, debugOverWire);
      listener.listen();
    });
    Isolate.spawn(_sessionMasterIsolate, [sessionResponse.sendPort]);
  }
}

void _mainListenerIsolate(List args) {
  var listener = new HttpListenerIsolateImpl(args[0] as int, args[1] as int, args[3] as SendPort, args[4] as bool);
  listener.listen();
}

void _sessionMasterIsolate(List args) {
  var sessionListener = new SessionMaster(1);
  (args[0] as SendPort).send(sessionListener.httpSendPort);
}

void _defaultLogger(String msg, bool isError) {
  if (isError) {
    print('[ERROR] $msg');
  } else {
    print(msg);
  }
}
