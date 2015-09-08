library a_la_carte.server;

import 'dart:isolate';

import 'package:d17/d17.dart';

import 'src/http_listener_isolate.dart';
import 'src/session_master.dart';
import 'src/a_la_carte_module.dart';

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
        Isolate.spawn(_mainListenerIsolate,
            [port, i, couchPort, sessionPort, debugOverWire]);
      }
      final injector = new Injector(new ALaCarteModule(
          httpServerPort: port,
          sessionMasterSendPort: sessionPort,
          debugOverWire: debugOverWire));
      final HttpListenerIsolate listener =
          injector.getInstance(HttpListenerIsolate);
      listener.listen();
    });
    Isolate.spawn(_sessionMasterIsolate,
        [port, null, couchPort, null, debugOverWire, sessionResponse.sendPort]);
  }
}

void _mainListenerIsolate(List args) {
  final injector = new Injector(new ALaCarteModule(
      httpServerPort: args[0],
      sessionMasterSendPort: args[3],
      debugOverWire: args[4],
      couchDbPort: args[2]));
  final HttpListenerIsolate listener =
      injector.getInstance(HttpListenerIsolate);
  listener.listen();
}

void _sessionMasterIsolate(List args) {
  final injector = new Injector(
      new ALaCarteModule(httpServerPort: args[0], debugOverWire: args[4]));
  final SessionMaster sessionListener = injector.getInstance(SessionMaster);
  sessionListener.spinUpConnectors();
  (args[5] as SendPort).send(sessionListener.httpSendPort);
}
