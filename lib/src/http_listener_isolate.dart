part of a_la_carte.server;

Future _writeShelfResponse(
    StreamSink<List<int>> output, shelf.Response response) {
  final completer = new Completer();
  final encoder = new Utf8Encoder();
  output.add(encoder.convert(
      'HTTP/1.1 ${response.statusCode} ${statusReasons[response.statusCode]}\r\n'));
  response.headers.forEach((headerName, headerValues) {
    if (headerValues is String) {
      output.add(encoder.convert('$headerName: $headerValues\r\n'));
    } else {
      assert(headerValues is List<String>);
      for (var headerValue in headerValues) {
        output.add(encoder.convert('$headerName: $headerValue\r\n'));
      }
    }
  });
  output.add(encoder.convert('Transfer-Encoding: chunked\r\n'));
  output.add(encoder.convert('Access-Control-Allow-Origin: *\r\n'));
  output.add([13, 10]);
  response.read().listen((data) {
    output.add(encoder.convert('${data.length.toRadixString(16)}\r\n'));
    output.add(data);
    output.add([13, 10]);
  }, onDone: () {
    output.add([48, 13, 10, 13, 10]);
    output.close();
    completer.complete();
  }, onError: (error, stackTrace) {
    output.addError(error, stackTrace);
    completer.completeError(error, stackTrace);
  });
  return completer.future;
}

const Map<int, String> statusReasons = const <int, String>{
  100: 'Continue', //[ RFC7231, Section 6.2.1]
  101: 'Switching Protocols', //[ RFC7231, Section 6.2.2]
  102: 'Processing', //[ RFC2518]
  //103-199	Unassigned
  200: 'OK', //[ RFC7231, Section 6.3.1]
  201: 'Created', //[ RFC7231, Section 6.3.2]
  202: 'Accepted', //[ RFC7231, Section 6.3.3]
  203: 'Non-Authoritative Information', //[ RFC7231, Section 6.3.4]
  204: 'No Content', //[ RFC7231, Section 6.3.5]
  205: 'Reset Content', //[ RFC7231, Section 6.3.6]
  206: 'Partial Content', //[ RFC7233, Section 4.1]
  207: 'Multi-Status', //[ RFC4918]
  208: 'Already Reported', //[ RFC5842]
  //209-225	Unassigned
  226: 'IM Used', //[ RFC3229]
  //227-299	Unassigned
  300: 'Multiple Choices', //[ RFC7231, Section 6.4.1]
  301: 'Moved Permanently', //[ RFC7231, Section 6.4.2]
  302: 'Found', //[ RFC7231, Section 6.4.3]
  303: 'See Other', //[ RFC7231, Section 6.4.4]
  304: 'Not Modified', //[ RFC7232, Section 4.1]
  305: 'Use Proxy', //[ RFC7231, Section 6.4.5]
  //306: '(Unused)', //[ RFC7231, Section 6.4.6]
  307: 'Temporary Redirect', //[ RFC7231, Section 6.4.7]
  308: 'Permanent Redirect', //[ RFC7538]
  //309-399	Unassigned
  400: 'Bad Request', //[ RFC7231, Section 6.5.1]
  401: 'Unauthorized', //[ RFC7235, Section 3.1]
  402: 'Payment Required', //[ RFC7231, Section 6.5.2]
  403: 'Forbidden', //[ RFC7231, Section 6.5.3]
  404: 'Not Found', //[ RFC7231, Section 6.5.4]
  405: 'Method Not Allowed', //[ RFC7231, Section 6.5.5]
  406: 'Not Acceptable', //[ RFC7231, Section 6.5.6]
  407: 'Proxy Authentication Required', //[ RFC7235, Section 3.2]
  408: 'Request Timeout', //[ RFC7231, Section 6.5.7]
  409: 'Conflict', //[ RFC7231, Section 6.5.8]
  410: 'Gone', //[ RFC7231, Section 6.5.9]
  411: 'Length Required', //[ RFC7231, Section 6.5.10]
  412: 'Precondition Failed', //[ RFC7232, Section 4.2]
  413: 'Payload Too Large', //[ RFC7231, Section 6.5.11]
  414: 'URI Too Long', //[ RFC7231, Section 6.5.12]
  415: 'Unsupported Media Type', //[ RFC7231, Section 6.5.13]
  416: 'Range Not Satisfiable', //[ RFC7233, Section 4.4]
  417: 'Expectation Failed', //[ RFC7231, Section 6.5.14]
  //418-420	Unassigned
  421: 'Misdirected Request', //[ RFC7540, Section 9.1.2]
  422: 'Unprocessable Entity', //[ RFC4918]
  423: 'Locked', //[ RFC4918]
  424: 'Failed Dependency', //[ RFC4918]
  //425: 'Unassigned
  426: 'Upgrade Required', //[ RFC7231, Section 6.5.15]
  //427: 'Unassigned',
  428: 'Precondition Required', //[ RFC6585]
  429: 'Too Many Requests', //[ RFC6585]
  //430: 'Unassigned',
  431: 'Request Header Fields Too Large', //[ RFC6585]
  //432-499	Unassigned
  500: 'Internal Server Error', //[ RFC7231, Section 6.6.1]
  501: 'Not Implemented', //[ RFC7231, Section 6.6.2]
  502: 'Bad Gateway', //[ RFC7231, Section 6.6.3]
  503: 'Service Unavailable', //[ RFC7231, Section 6.6.4]
  504: 'Gateway Timeout', //[ RFC7231, Section 6.6.5]
  505: 'HTTP Version Not Supported', //[ RFC7231, Section 6.6.6]
  506: 'Variant Also Negotiates', //[ RFC2295]
  507: 'Insufficient Storage', //[ RFC4918]
  508: 'Loop Detected', //[ RFC5842]
  //509: 'Unassigned',
  510: 'Not Extended', //[ RFC2774]
  511: 'Network Authentication Required', //[ RFC6585]
  //512-599	Unassigned
};

class HttpListenerIsolate extends SessionClient {
  final int _port;
  final int _isolateId;

  static const String _selfClosingPage = """
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <script>close();</script>
    <title>A la carte</title>
  </head>
  <body></body>
</html>

""";

  // TODO: Move these to a config file.
  static const String _user = 'a_la_carte';
  static const String _password = 'a_la_carte';
  static const int _responseShouldCascade = 550;
  final int couchPort;
  final bool _debugOverWire;
  PolicyValidator _policyModule;
  static const List<String> _servedStatic = const [
    //'index.html',
    'a_la_carte.scss',
    'a_la_carte.scss.css',
    'index.bootstrap.dart',
    'index.bootstrap.dart.js',
    'index.bootstrap.dart.js.map',
    'index.dart',
    'index.dart.js',
    'index.html.polymer.bootstrap.dart',
    'index.html.polymer.bootstrap.dart.js',
    'index.html.polymer.bootstrap.dart.js.map',
    'index.html.web_components.bootstrap.dart',
    'index.html.web_components.bootstrap.dart.js',
    'index.html.web_components.bootstrap.dart.js.map',
    'components',
    'packages',
    '_static'
  ];

  final Map<String, DateTime> _refresh = new Map<String, DateTime>();
  final Map<String, Timer> _refreshTimeout = new Map<String, Timer>();
  final Map<String, Ref<bool>> _cancellationListener =
      new Map<String, Ref<bool>>();
  final Map<String, Completer> _sessionsWithNoSpecialKnowledgeByPsid =
      new Map<String, Completer<PolicyIdentity>>();
  final Set<String> sessionsThatHaveBeenSentTheirCredentials =
      new Set<String>();

  CouchDbBackend _couchConnection;

  HttpListenerIsolate(int this._port, int this._isolateId, int this.couchPort,
      SendPort sessionMasterSendPort, bool this._debugOverWire)
      : super(sessionMasterSendPort);

  shelf.Handler _addCookies(shelf.Handler innerHandler) =>
      (shelf.Request request) {
    String psid = null;
    String tsid = null;
    bool tsidCookieIsNew = false;

    if (request.headers.containsKey(r'Cookie')) {
      var rawCookie = request.headers['Cookie'];
      for (String cookie in rawCookie.split(r'; ')) {
        if (cookie.startsWith('TSID=')) {
          tsid = cookie.split('=')[1];
          _defaultLogger(
              '$tsid: Starting request for ${request.url} with an existing cookie.',
              false);
          if (psid != null) break;
        } else if (cookie.startsWith('PSID=')) {
          psid = cookie.split('=')[1];
          if (tsid != null) break;
        }
      }
    }
    if (tsid == null) {
      tsid = new Uuid().v1();
      _defaultLogger(
          '$tsid: Starting request for ${request.url} with a new cookie.',
          false);
      tsidCookieIsNew = true;
    }
    Completer psidSessionCompleter;
    if (psid != null) {
      if (_sessionsWithNoSpecialKnowledgeByPsid[psid] != null) {
        psidSessionCompleter = _sessionsWithNoSpecialKnowledgeByPsid[psid];
      } else {
        psidSessionCompleter = new Completer();
      }
    }

    var sessionContainerFuture = getSessionContainer(tsid, psid);
    request = request.change(
        context: {
      'session': sessionContainerFuture,
      'loginCompleter': psidSessionCompleter,
      'tsid': tsid
    });
    var result = innerHandler(request);

    if (result is Future) {
      return result.then((innerResult) => _processCookieResult(innerResult,
          tsid, tsidCookieIsNew, sessionContainerFuture, psid,
          request.context['timestamp'], psidSessionCompleter));
    } else {
      assert(result is shelf.Response);
      return _processCookieResult(result, tsid, tsidCookieIsNew,
          sessionContainerFuture, psid, request.context['timestamp'],
          psidSessionCompleter);
    }
  };

  Future<shelf.Response> _processCookieResult(shelf.Response response,
      String tsid, bool tsidCookieIsNew,
      Future<SessionClientRow> sessionContainerFuture, String psid,
      int timestamp, Completer psidSessionCompleter) async {
    bool psidCookieIsNew = false;

    if (psid == null) {
      var sessionData = await sessionContainerFuture;
      psid = sessionData.psid;
      psidCookieIsNew = true;
    }

    var responseHeaders = {'Access-Control-Allow-Credentials': 'true'};

    var policy;
    final psidUri = Uri.parse('/a_la_carte/${Uri.encodeComponent(psid)}');

    if (tsidCookieIsNew) {
      responseHeaders['Set-Cookie'] = ["TSID=${tsid}; Path=/"];
      if (!psidCookieIsNew) {
        if (_sessionsWithNoSpecialKnowledgeByPsid[psid] == null) {
          final cancellationRef = new Ref.withValue(true);
          _cancellationListener[psid] = cancellationRef;
          var sessionData = await sessionContainerFuture;
          _sessionsWithNoSpecialKnowledgeByPsid[psid] = psidSessionCompleter;
          _policyModule
              .createPolicyIdentityFromState(
                  sessionData, _user, _couchConnection, timestamp, this)
              .then((PolicyIdentity policy) async {
            await sessionContainerFuture;
            pushClientAuthorizationToListener(
                tsid, new DateTime.now().millisecondsSinceEpoch, psid, policy,
                isPassivePush: true);
            if (cancellationRef.value) {
              _sessionsWithNoSpecialKnowledgeByPsid[psid].complete(policy);
            } else {
              throw new OperationCanceled();
            }
          }).catchError((error, stackTrace) {
            if (error is OperationCanceled) return;
            if (cancellationRef.value &&
                !_sessionsWithNoSpecialKnowledgeByPsid[psid].isCompleted) {
              _sessionsWithNoSpecialKnowledgeByPsid[psid].completeError(
                  error, stackTrace);
            }
          });
        }
      } else {
        final DateTime expires = new DateTime.now().add(new Duration(days: 15));
        responseHeaders['Set-Cookie'].add(
            "PSID=${psid}; Path=/; Expires=${HttpDate.format(expires)}; HttpOnly");
      }
    } else if (psidCookieIsNew) {
      final DateTime expires = new DateTime.now().add(new Duration(days: 15));
      responseHeaders['Set-Cookie'] = [
        "PSID=${psid}; Path=/; Expires=${HttpDate.format(expires)}; HttpOnly"
      ];
    }
    return response.change(headers: responseHeaders);
  }

  bool _shouldCascade(shelf.Response response) {
    if (response.statusCode == _responseShouldCascade) return true;
    return false;
  }

  Future listen() async {
    final socket =
        await ServerSocket.bind(InternetAddress.ANY_IP_V4, _port, shared: true);
    assert(_policyModule == null);
    _policyModule = new OAuth2PolicyValidator();
    assert(_couchConnection == null);
    _couchConnection = new CouchDbBackend(
        couchPort, _user, _password, _policyModule, _debugOverWire);

    var cascadeHandlers = new shelf.Cascade(shouldCascade: _shouldCascade)
        .add(_authLandingHandler)
        .add(_authLoginHandler)
        .add(_authSessionHandler)
        .add(_handleJsonRequest(_couchConnection))
        .add(_handleStaticFileRequest);

    var handler = const shelf.Pipeline()
        .addMiddleware(_addTimestamp)
        .addMiddleware(shelf.logRequests())
        .addMiddleware(_addCookies)
        .addHandler(cascadeHandlers.handler);

    var server = new HttpServer.listenOn(socket);
    _logTopLevelErrors(server, handler);
    print('${new DateTime.now()}\tServing at http://'
        '${server.address.host}:${server.port} (Listener $_isolateId)');
  }

  shelf.Handler _addTimestamp(shelf.Handler innerHandle) =>
      (shelf.Request request) {
    request = request.change(
        context: {'timestamp': new DateTime.now().millisecondsSinceEpoch});
    return innerHandle(request);
  };

  bool _isJsonRequest(shelf.Request request) {
    if (request.method == 'GET' || request.method == 'HEAD') {
      var accept = request.headers['Accept'];
      if (accept != null &&
          accept is String &&
          accept.contains('application/json')) return true;
    } else if (request.method == 'PUT' || request.method == 'POST') {
      var contentType = request.headers['Content-Type'];
      if (contentType != null &&
          contentType is String &&
          contentType.contains('application/json')) {
        return true;
      }
    } else if (request.method == 'DELETE') {
      return true;
    }
    return false;
  }

  shelf.Handler _handleJsonRequest(CouchDbBackend datastore) =>
      (shelf.Request request) {
    if (!_isJsonRequest(request)) {
      return new shelf.Response(_responseShouldCascade);
    }
    request.hijack((input, output) => datastore.hijackRequest(input, output,
        request.method, request.requestedUri, request.headers,
        request.context['loginCompleter'] == null
            ? null
            : request.context['loginCompleter'].future,
        sessionsThatHaveBeenSentTheirCredentials, request.context['tsid']));
  };

  dynamic _authLandingHandler(shelf.Request request) async {
    if (request.url.path == '_auth/landing') {
      final state = request.url.queryParameters['state'];
      final SessionClientRow session = await request.context['session'];
      if (_sessionsWithNoSpecialKnowledgeByPsid[session.psid] != null) {
        _cancellationListener[session.psid].value = false;
      }
      return (_policyModule as OAuth2PolicyValidator)
          .createPolicyIdentityFromState(session, _user, _couchConnection,
              request.context['timestamp'], this,
              code: request.url.queryParameters['code'], notifyOnAuth: state)
          .then((identity) {
        sessionsThatHaveBeenSentTheirCredentials.add(request.context['tsid']);
        if (!_sessionsWithNoSpecialKnowledgeByPsid[session.psid].isCompleted) {
          _sessionsWithNoSpecialKnowledgeByPsid[session.psid]
              .complete(identity);
        }
        return new shelf.Response.ok(_selfClosingPage,
            headers: {'Content-Type': 'text/html; charset=utf-8'});
      });
    } else {
      return new shelf.Response(_responseShouldCascade);
    }
  }

  dynamic _authLoginHandler(shelf.Request request) async {
    if (request.url.path == '_auth/login') {
      Future<SessionClientRow> sessionFuture = request.context['session'];
      try {
        var session = await sessionFuture;
        if (_sessionsWithNoSpecialKnowledgeByPsid[session.psid] == null) {
          final cancellationRef = new Ref.withValue(true);
          _cancellationListener[session.psid] = cancellationRef;
          _sessionsWithNoSpecialKnowledgeByPsid[session.psid] = new Completer();

          _policyModule
              .createPolicyIdentityFromState(session, _user, _couchConnection,
                  request.context['timestamp'], this, isPassivePush: false)
              .then((PolicyIdentity policy) async {
            await sessionFuture;
            pushClientAuthorizationToListener(session.tsid,
                new DateTime.now().millisecondsSinceEpoch, session.psid, policy,
                isPassivePush: true);
            if (cancellationRef.value) {
              _sessionsWithNoSpecialKnowledgeByPsid[session.psid]
                  .complete(policy);
            } else {
              throw new OperationCanceled();
            }
          }).catchError((error, stackTrace) {
            if (error is OperationCanceled) return;
            if (cancellationRef.value &&
                !_sessionsWithNoSpecialKnowledgeByPsid[
                session.psid].isCompleted) {
              _sessionsWithNoSpecialKnowledgeByPsid[session.psid].completeError(
                  error, stackTrace);
            }
          });
        }
        await _sessionsWithNoSpecialKnowledgeByPsid[session.psid].future;
        final response = new shelf.Response(200,
            body: '{"ok": true}',
            headers: {"Content-Type": "application/json"},
            encoding: Encoding.getByName('identity'));
        return response;
      } catch (error, stackTrace) {
        if (error is PolicyStateError) {
          shelf.Response response;
          if (error.redirectUri != null) {
            response = new shelf.Response(401,
                body: '{"error": "must_authenticate", "message": "You must log in before '
                'performing this action.", "auth_uri": "${error.redirectUri}", "auth_watcher_id": "${error.awakenId}", "auth_watcher_rev": "${error.awakenRev}"}',
                headers: {"Content-Type": "application/json"},
                encoding: Encoding.getByName('identity'));
          } else {
            final encoder = new JsonEncoder();
            response = new shelf.Response.internalServerError(
                body: encoder.convert(error.replyFromDbBackend),
                headers: {"Content-Type": "application/json"},
                encoding: Encoding.getByName('identity'));
          }
          return response;
        } else {
          String body;
          if (_debugOverWire) {
            final JsonEncoder encoder = new JsonEncoder.withIndent('    ');
            final Map error_info = {
              'error': error.toString(),
              'stack_trace': stackTrace.toString()
            };
            body = '''{
  "error":"internal_server_error",
  "message": "I couldn\'t connect to the database. Contact your database administrator.",
  "dart_error": ${encoder.convert(error_info)          }
}''';
          } else {
            body = '''{
    "error":"internal_server_error",
    "message": "I couldn\'t connect to the database. Contact your database administrator."
  }''';
          }
          final response = new shelf.Response.internalServerError(
              body: body,
              headers: {"Content-Type": "application/json"},
              encoding: Encoding.getByName('identity'));
          return response;
        }
      }
    } else {
      return new shelf.Response(_responseShouldCascade);
    }
  }

  dynamic _authSessionHandler(shelf.Request request) async {
    if (request.url.path == '_auth/session') {
      final SessionClientRow session = await request.context['session'];
      String body = '''{
  "tsid": "${session.tsid}",
  "psid": "${session.psid}",
  "email": "${session.email}",
  "fullName": "${session.fullName}",
  "picture": "${session.picture}"
}
''';
      return new shelf.Response.ok(body,
          headers: {'Content-Type': 'application/json'});
    } else {
      return new shelf.Response(_responseShouldCascade);
    }
  }

  dynamic _handleStaticFileRequest(shelf.Request request) {
    _serveStaticFile(request);
    if (request.url.path != '_auth' &&
        request.url.path != '' &&
        !_servedStatic.contains(request.url.pathSegments[0]) &&
        !request.url.pathSegments[0].contains('_buildLogs') &&
        request.url.path != 'favicon.ico') {
      return new shelf.Response.movedPermanently('/#${request.url}');
    }
    return _serveStaticFile(request);
  }

  Future<shelf.Response> _serveStaticFile(shelf.Request request) async {
    final scriptUri = Platform.script;
    if (request.method != 'GET' && request.method != 'HEAD') {
      return new shelf.Response.forbidden(null);
    }
    String newPath = '/';
    for (var i = 0; i < scriptUri.pathSegments.length - 2; i++) {
      newPath += scriptUri.pathSegments[i] + '/';
    }
    return _staticFileServer(newPath + 'build/web/')(request);
  }

  void _logTopLevelErrors(Stream<HttpRequest> requests, shelf.Handler handler) {
    catchTopLevelErrors(() {
      requests
          .listen((HttpRequest request) => io.handleRequest(request, handler));
    }, (error, stackTrace) {
      _logError(
          'Asynchronous error on isolate ${Isolate.current.hashCode}.\n$error',
          stackTrace);
    });
  }
}

shelf.Handler _staticFileServer(String path, {String defaultName: 'index.html',
    Future<Map<String, Object>> otherHeaders: null, bool isNotFound: false,
    String overrideFile: null}) => (shelf.Request request) async {
  if (request.method != 'GET' && request.method != 'HEAD') {
    return new shelf.Response.forbidden(null);
  }
  var filePath = path + request.url.path;
  if (overrideFile != null) {
    filePath = overrideFile;
  } else if (filePath.endsWith('/')) {
    filePath += defaultName;
  }

  DateTime lastModified;
  int fileLength;
  dynamic body;

  final serveUri = new Uri(scheme: 'file', path: filePath);
  final serveFile = new File.fromUri(serveUri);

  final stat = await serveFile.stat();
  if (stat.type == FileSystemEntityType.NOT_FOUND) {
    if (isNotFound) {
      return new shelf.Response.internalServerError(
          body: 'File not found $filePath while serving 404 page.');
    }
    return _staticFileServer(path,
        otherHeaders: otherHeaders,
        isNotFound: true,
        overrideFile: path + '_static/404.html')(request);
  } else {
    lastModified = stat.modified;
    //Since lastModified might be more precise than 1 second.
    lastModified = lastModified;
    fileLength = stat.size;
  }
  body = serveFile;

  final contentType =
      contentTypeByExtension(filePath.replaceAll(new RegExp(r'^.*\.'), '.'));
  var defaultHeaders = {
    'Last-Modified': HttpDate.format(lastModified),
    'Cache-Control': 'public, max_age=600',
    'Expires':
        HttpDate.format(new DateTime.now().add(new Duration(minutes: 10))),
    'Date': HttpDate.format(lastModified),
    'Vary': '*',
    'Content-Type': contentType
  };

  var connection = request.headers['Connection'];
  if (connection is String && connection.split(', ').contains('keep-alive')) {
    defaultHeaders['Connection'] = 'keep-alive';
    defaultHeaders['Keep-Alive'] = 'timeout=5, max=256';
  }

  Map<String, Object> headers;

  final ifModifiedSince = request.headers['If-Modified-Since'];
  if (!isNotFound && ifModifiedSince != null) {
    final ifModifiedSinceDate = HttpDate.parse(ifModifiedSince);
    if (lastModified
        .subtract(new Duration(seconds: 1))
        .isBefore(ifModifiedSinceDate)) {
      if (otherHeaders != null) {
        headers = await otherHeaders;
      } else {
        headers = {};
      }
      headers.addAll(defaultHeaders);
      return new shelf.Response.notModified(headers: headers);
    }
  }

  if (body is File) {
    body = body.openRead();
  }

  if (otherHeaders != null) {
    headers = await otherHeaders;
  } else {
    headers = {};
  }

  headers.addAll(defaultHeaders);
  if (isNotFound) {
    return new shelf.Response.notFound(body, headers: headers);
  }
  return new shelf.Response.ok(body, headers: headers);
};

String contentTypeByExtension(String _extension) {
  switch (_extension) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.txt':
      return 'text/plain; charset=utf-8';
    case '.js':
      return 'application/javascript';
    case '.dart':
      return 'application/dart';
    default:
      return 'application/octet-stream';
  }
}

/// Run [callback] and capture any errors that would otherwise be top-leveled.
///
/// If [this] is called in a non-root error zone, it will just run [callback]
/// and return the result. Otherwise, it will capture any errors using
/// [runZoned] and pass them to [onError].
catchTopLevelErrors(callback(), void onError(error, StackTrace stackTrace)) {
  if (Zone.current.inSameErrorZone(Zone.ROOT)) {
    return runZoned(callback, onError: onError);
  } else {
    return callback();
  }
}

// TODO(kevmoo) A developer mode is needed to include error info in response
// TODO(kevmoo) Make error output plugable. stderr, logging, etc
shelf.Response _logError(String message, [StackTrace stackTrace]) {
  var chain = new stack_trace.Chain.current();
  if (stackTrace != null) {
    chain = new stack_trace.Chain.forTrace(stackTrace);
  }
  chain = chain
      .foldFrames((frame) => frame.isCore || frame.package == 'shelf').terse;

  stderr.writeln('ERROR - ${new DateTime.now()}');
  stderr.writeln(message);
  stderr.writeln(chain);
  return new shelf.Response.internalServerError();
}
