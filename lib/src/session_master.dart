part of a_la_carte.server;

class SessionMaster {
  final int delegates;
  int _initialLoadOrder = 0;
  final Map<String, SendPort> _sessionHandlers;
  final Map<String, SendPort> _oauthIdentityHandlers;
  final SplayTreeMap<int, SendPort> _sessionHandlerByOrderOfLoad;
  final Map<SendPort,int> _sessionHandlerLoad;
  final ReceivePort _sessionReceivePort;
  final ReceivePort _httpReceivePort;
  
  SendPort get httpSendPort => _httpReceivePort.sendPort;
  
  SessionMaster(int this.delegates)
      : _sessionHandlers = new Map<String, SendPort>()
      , _oauthIdentityHandlers = new Map<String, SendPort>()
      , _sessionHandlerByOrderOfLoad = new SplayTreeMap<int, SendPort>()
      , _sessionHandlerLoad = new Map<SendPort,int>()
      , _sessionReceivePort = new ReceivePort()
      , _httpReceivePort = new ReceivePort() {
    print('${new DateTime.now()}\tSession master spinning up.');
    _sessionReceivePort.listen(listenForSessionListenerRequest);
    _httpReceivePort.listen(listenForHttpListenerRequest);
    for (var i = 0; i < delegates; i++) {
      Isolate.spawn(_createSessionDelegate, [_sessionReceivePort.sendPort, i]);
    }
  }

  void listenForHttpListenerRequest(List args) {
    var basicFunction = args[0] as String;
    switch (basicFunction) {
      case 'getSessionDelegateByTsid':
        _getSessionDelegateByTsid(args[1], args[2]);
        return;
      case 'getNewSessionDelegate':
        _getNewSessionDelegate(args[1], args[2]);
        return;
      default:
        throw new StateError('SessionMaster did not understand $basicFunction message from http listener.');
    }
  }

  void _getNewSessionDelegate(SendPort responsePort, String uuid) {
    var newPort = _sessionHandlerByOrderOfLoad[_sessionHandlerByOrderOfLoad.firstKey()];
    _sessionAdded(uuid, newPort);
    responsePort.send(_sessionHandlerByOrderOfLoad[_sessionHandlerByOrderOfLoad.firstKey()]);
  }
  
  void listenForSessionListenerRequest(List args) {
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
      default:
        throw new StateError('SessionMaster did not understand $basicFunction message from session delegate.');
    }
  }
  
  

  void _sessionAdded(String uuid, SendPort myPort) {
    _sessionHandlers[uuid] = myPort;
    final oldLoad = _sessionHandlerLoad[myPort];
    _sessionHandlerLoad[myPort] += delegates;
    _sessionHandlerByOrderOfLoad.remove(oldLoad);
    _sessionHandlerByOrderOfLoad[_sessionHandlerLoad[myPort]] = myPort;
  }
  
  void _getSessionDelegateByTsid(String tsid, SendPort responsePort) {
    var sessionDelegate = _sessionHandlers[tsid];
    responsePort.send([sessionDelegate]);
  }
  
  void _sessionDropped(String tsid, SendPort myPort) {
    var sessionDelegate = _sessionHandlers[tsid];
    final oldLoad = _sessionHandlerLoad[myPort];
    _sessionHandlerLoad[myPort] -= delegates;
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
    var sessionDelegate = new _SessionListener(args[0], args[1]);
    sessionDelegate.listen();
  }
}
