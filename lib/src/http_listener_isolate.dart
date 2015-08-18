part of a_la_carte.server;

class HttpListenerIsolate extends SessionClient {
  final int _port;
  final int _isolateId;

  static const String _selfClosingPage = """
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <script type=async>close();</script>
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
  PolicyValidator _policyModule;
  static const List<String> servedStatic = const [
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

  final Map<String, DateTime> _refresh;
  final Map<String, Timer> _refreshTimeout;
  final Map<int, DateTime> _httpRequestTimestamps =
      new Map<int, DateTime>(); //This really should be a WeakMap.

  HttpListenerIsolate(int this._port, int this._isolateId, int this.couchPort,
      SendPort sessionMasterSendPort)
      : super(sessionMasterSendPort),
        _refresh = new Map<String, DateTime>(),
        _refreshTimeout = new Map<String, Timer>();

  shelf.Handler _addCookies(shelf.Handler innerHandler) =>
      (shelf.Request request) {
        String psid = null;
        bool psidCookieIsNew = false;
        String tsid = null;
        bool tsidCookieIsNew = false;

        if (request.headers.containsKey(r'Cookie')) {
          var rawCookie = request.headers['Cookie'];
          for (String cookie in rawCookie.split(r'; ')) {
            if (cookie.startsWith('TSID=')) {
              tsid = cookie.split('=')[1];
              if (psid != null) break;
            } else if (cookie.startsWith('PSID=')) {
              psid = cookie.split('=')[1];
              if (tsid != null) break;
            }
          }
        }
        if (tsid == null) {
          tsid = new Uuid().v1();
          tsidCookieIsNew = true;
        }

        var sessionContainerFuture = getSessionContainer(tsid, psid);

        request = request.change(context: {'session': sessionContainerFuture});
        var result = innerHandler(request);

        shelf.Response processResult(shelf.Response response) {
          var responseHeaders = new Map<String, Object>.from(response.headers);
          if (tsidCookieIsNew) {
            responseHeaders['Set-Cookie'] = [
              "TSID=${tsid}; Path=/; "
                  "HttpOnly"
            ];
          }
          return response.change(headers: responseHeaders);
        }
        if (result is Future) {
          return result.then(processResult);
        } else {
          assert(result is shelf.Response);
          return processResult(result);
        }
      };

  bool _shouldCascade(shelf.Response response) {
    if (response.statusCode == _responseShouldCascade) return true;
    return false;
  }

  Future listen() async {
    final socket =
        await ServerSocket.bind(InternetAddress.ANY_IP_V4, _port, shared: true);
    assert(_policyModule == null);
    _policyModule = new OAuth2PolicyValidator();
    final couchConnection =
        new CouchDbBackend(couchPort, _user, _password, _policyModule);

    var cascadeHandlers = new shelf.Cascade(shouldCascade: _shouldCascade)
        .add(_authCallbackHandler)
        .add(_handleJsonRequest(couchConnection))
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
        _httpRequestTimestamps[request.hashCode] = new DateTime.now();
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
        return _policyModule
            .createEmptyPolicyIdentity(_user)
            .then((policyIdentity) {
          request.hijack((input, output) => datastore.hijackRequest(
              input,
              output,
              request.method,
              request.requestedUri,
              request.headers,
              policyIdentity));
        });
      };

  dynamic _authCallbackHandler(shelf.Request request) {
    if (request.url.path == '_auth/landing') {
      (_policyModule as OAuth2PolicyValidator).createPolicyIdentityFromState(
          request.url.queryParameters['code'],
          request.url.queryParameters['state'],
          _user);
      var completer = new Completer();
      return completer.future;
    } else {
      return new shelf.Response(_responseShouldCascade);
    }
  }

  dynamic _handleStaticFileRequest(shelf.Request request) {
    _serveStaticFile(request);
    if (request.url.path != '_auth' &&
        request.url.path != '' &&
        !servedStatic.contains(request.url.pathSegments[0]) &&
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

shelf.Handler _staticFileServer(String path,
        {String defaultName: 'index.html',
        Future<Map<String, Object>> otherHeaders: null,
        bool isNotFound: false,
        String overrideFile: null}) =>
    (shelf.Request request) async {
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

      final contentType = contentTypeByExtension(
          filePath.replaceAll(new RegExp(r'^.*\.'), '.'));
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
      if (connection is String &&
          connection.split(', ').contains('keep-alive')) {
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
      .foldFrames((frame) => frame.isCore || frame.package == 'shelf')
      .terse;

  stderr.writeln('ERROR - ${new DateTime.now()}');
  stderr.writeln(message);
  stderr.writeln(chain);
  return new shelf.Response.internalServerError();
}
