part of a_la_carte.server;

class SendPortEntry extends LinkedListEntry<SendPortEntry> {
  final SendPort sendPort;
  SendPortEntry(SendPort this.sendPort);
}

class SessionMaster {
  final Map<String, SendPort> _sessionHandlers;
  final Map<String, SendPort> _oauthIdentityHandlers;
  final LinkedList<SendPortEntry> _sessionHandlerByOrderOfLoad;
  final Map<SendPort,int> _sessionHandlerLoad;
  final ReceivePort _sessionReceivePort;
  final ReceivePort _httpReceivePort;
  
  SendPort get httpSendPort => _httpReceivePort.sendPort;
  
  SessionMaster(int delegates)
      : _sessionHandlers = new Map<String, SendPort>()
      , _oauthIdentityHandlers = new Map<String, SendPort>()
      , _sessionHandlerByOrderOfLoad = new LinkedList<SendPortEntry>()
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
      case 'getSessionDelegateByUuid':
        _getSessionDelegateByUuid(args[1], args[2]);
        return;
      case 'getNewSessionDelegate':
        _getNewSessionDelegate(args[2]);
        return;
      default:
        throw new StateError('SessionMaster did not understand $basicFunction message from http listener.');
    }
  }

  void _getNewSessionDelegate(SendPort responsePort) {
    responsePort.send(_sessionHandlerByOrderOfLoad.first.sendPort);
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
    _sessionHandlerLoad[myPort]++;
  }
  
  void _getSessionDelegateByUuid(String uuid, SendPort responsePort) {
    var sessionDelegate = _sessionHandlers[uuid];
    responsePort.send([sessionDelegate]);
  }
  
  void _sessionDropped(String uuid, SendPort myPort) {
    var sessionDelegate = _sessionHandlers[uuid];
    _sessionHandlerLoad[myPort]--;
    _sessionHandlers.remove(uuid);
    myPort.send(['confirmedSessionDropped', uuid]);
    assert(sessionDelegate != null);
  }
  
  void _createdSessionDelegate(SendPort sendPort) {
    _sessionHandlerLoad[sendPort] = 0;
    var entry = new SendPortEntry(sendPort);
    _sessionHandlerByOrderOfLoad.addFirst(entry);
  }
  
  static void _createSessionDelegate(List args) {
    var sessionDelegate = new _SessionListener(args[0], args[1]);
    sessionDelegate.listen();
  }
}
