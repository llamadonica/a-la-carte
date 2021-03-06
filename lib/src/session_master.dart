library a_la_carte.server.session_master;

import 'dart:collection';
import 'dart:isolate';

import 'package:d17/d17.dart';

import 'logger.dart';
import 'session_listener.dart';

abstract class SessionMaster {
  SendPort get httpSendPort;
  void spinUpConnectors();
}

class SessionMasterImpl extends SessionMaster {
  @Inject(name: 'a_la_carte.server.session_master.quantityOfSessionDelegates')
  int _delegates;

  int _initialLoadOrder = 0;
  final Map<String, SendPort> _sessionHandlers;
  final Map<String, List<SendPort>> _sessionHandlerFutures = new Map();
  final SplayTreeMap<int, SendPort> _sessionHandlerByOrderOfLoad;
  final Map<SendPort, int> _sessionHandlerLoad;
  final ReceivePort _sessionReceivePort;
  final ReceivePort _httpReceivePort;

  @inject Logger _defaultLogger;

  SendPort get httpSendPort => _httpReceivePort.sendPort;

  SessionMasterImpl()
      : _sessionHandlers = new Map<String, SendPort>(),
        _sessionHandlerByOrderOfLoad = new SplayTreeMap<int, SendPort>(),
        _sessionHandlerLoad = new Map<SendPort, int>(),
        _sessionReceivePort = new ReceivePort(),
        _httpReceivePort = new ReceivePort();

  void spinUpConnectors() {
    _defaultLogger('${new DateTime.now()}\tSession master spinning up.');
    _sessionReceivePort.listen(_listenForSessionListenerRequest);
    _httpReceivePort.listen(_listenForHttpListenerRequest);
    for (var i = 0; i < _delegates; i++) {
      Isolate.spawn(_createSessionDelegate, [_sessionReceivePort.sendPort, i]);
    }
  }

  void _listenForHttpListenerRequest(List args) {
    var basicFunction = args[0] as String;
    switch (basicFunction) {
      case 'getSessionDelegateByTsidOrCreateNew':
        _getSessionDelegateByTsidOrCreateNew(args[1], args[2]);
        return;
      default:
        throw new StateError(
            'SessionMaster did not understand $basicFunction message from http listener.');
    }
  }

  void _listenForSessionListenerRequest(List args) {
    var basicFunction = args[0] as String;
    switch (basicFunction) {
      case 'sessionAdded':
        _sessionAdded(args[1], args[2]);
        return;
      case 'sessionDropped':
        _sessionDropped(args[1], args[2]);
        return;
      case 'createdSessionDelegate':
        _createdSessionDelegate(args[1]);
        return;
      case 'interprocessLog':
        _defaultLogger(args[1], priority: LoggerPriority.values[args[2]]);
        return;
      default:
        throw new StateError(
            'SessionMaster did not understand $basicFunction message from session delegate.');
    }
  }

  void _sessionAdded(String uuid, SendPort myPort) {
    _sessionHandlers[uuid] = myPort;
    if (_sessionHandlerFutures.containsKey(uuid)) {
      for (var sendPort in _sessionHandlerFutures[uuid]) {
        sendPort.send([myPort, false]);
      }
      _sessionHandlerFutures.remove(uuid);
    }
  }

  void _getSessionDelegateByTsidOrCreateNew(
      String tsid, SendPort responsePort) {
    _defaultLogger('$tsid: Got a request for $tsid.');
    var sessionDelegate = _sessionHandlers[tsid];
    if (sessionDelegate != null) {
      _defaultLogger('$tsid: $tsid already exists.');
      responsePort.send([sessionDelegate, false]);
      return;
    }
    if (!_sessionHandlerFutures.containsKey(tsid)) {
      _defaultLogger('$tsid: $tsid must be created.');
      _sessionHandlerFutures[tsid] = [];
      sessionDelegate =
          _sessionHandlerByOrderOfLoad[_sessionHandlerByOrderOfLoad.firstKey()];
      final oldLoad = _sessionHandlerLoad[sessionDelegate];
      _sessionHandlerLoad[sessionDelegate] += _delegates;
      _sessionHandlerByOrderOfLoad.remove(oldLoad);
      _sessionHandlerByOrderOfLoad[_sessionHandlerLoad[sessionDelegate]] =
          sessionDelegate;
      responsePort.send([sessionDelegate, true]);
      return;
    }
    _sessionHandlerFutures[tsid].add(responsePort);
  }

  void _sessionDropped(String tsid, SendPort myPort) {
    var sessionDelegate = _sessionHandlers[tsid];
    final oldLoad = _sessionHandlerLoad[myPort];
    _sessionHandlerLoad[myPort] -= _delegates;
    _sessionHandlerByOrderOfLoad.remove(oldLoad);
    _sessionHandlerByOrderOfLoad[_sessionHandlerLoad[myPort]] = myPort;
    _sessionHandlers.remove(tsid);
    myPort.send(['confirmedSessionDropped', tsid]);
    assert(sessionDelegate != null);
  }

  void _createdSessionDelegate(SendPort sendPort) {
    _sessionHandlerLoad[sendPort] = _initialLoadOrder;
    _sessionHandlerByOrderOfLoad[_initialLoadOrder] = sendPort;
    _initialLoadOrder++;
  }

  static void _createSessionDelegate(List args) {
    void _interprocessLog(String message,
        {LoggerPriority priority: LoggerPriority.info}) {
      args[0].send(['interprocessLog', message, priority.index]);
    }
    var sessionDelegate =
        new SessionListener(args[0], args[1], _interprocessLog);
    sessionDelegate.listen();
  }
}
