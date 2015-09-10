library a_la_carte.server.http_listener;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:d17/d17.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:uuid/uuid.dart';
import 'package:stack_trace/stack_trace.dart' as stack_trace;

import 'authenticator.dart';
import 'session_client.dart';
import 'shelf_utils.dart';
import 'db_backend.dart';
import 'local_session_data.dart';
import 'http_db_backend_adapter.dart';
import 'logger.dart';

abstract class HttpListenerIsolate extends SessionClient {
  void listen();
  HttpListenerIsolate() : super();
}

class HttpListenerIsolateImpl extends HttpListenerIsolate {
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

  static String _errorPage(int errorNumber, String description) => """
<!DOCTYPE html>
<html>
<head><title>$errorNumber ${statusReasons[errorNumber]}</title></head>
<body bgcolor="white">
<center><h1>$errorNumber ${statusReasons[errorNumber]}</h1></center>
<p>
$description
</p>
<hr>
<center>A La Carte</center>
</body>
""";
  // TODO: Move these to a config file.
  static const String _user = 'a_la_carte';
  static const String _password = 'a_la_carte';
  static const int _responseShouldCascade = 550;
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
    '_static',
    'config.json'
  ];

  @inject
  DbBackend _dbConnection;

  @InjectAdapter(from: #_dbConnection)
  HttpDbBackendAdapter _dbHttpAdapter;

  @inject
  Authenticator _authenticationModule;

  @inject
  Logger defaultLogger;

  @Inject(name: 'a_la_carte.server.http_server_listener.httpServerPort')
  int _port;

  @Inject(name: 'a_la_carte.server.http_server_listener.sessionMasterSendPort')
  SendPort sessionMasterSendPort;

  final Map<String, DateTime> _refresh = new Map<String, DateTime>();
  final Map<String, Timer> _refreshTimeout = new Map<String, Timer>();

  @inject HttpListenerIsolateImpl();

  shelf.Handler _addCookies(shelf.Handler innerHandler) =>
      (shelf.Request request) async {
        String psid = null;
        String tsid = null;
        bool tsidCookieIsNew = false;
        bool askForPushSession = false;

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
        } else if (request.headers
                .containsKey(r'x-can-read-push-session-data') &&
            request.headers[r'x-can-read-push-session-data'] == 'true') {
          askForPushSession = true;
        }

        var session =
            await getSessionContainer(tsid, request.context['timestamp'], psid);
        session.refCount++;
        request = request.change(context: {
          'session': session,
          'askForPushSession': askForPushSession,
          'tsid': tsid
        });
        var result = innerHandler(request);

        if (result is Future) {
          return result.then((innerResult) => _processCookieResult(
              innerResult,
              tsid,
              tsidCookieIsNew,
              session,
              psid,
              request.context['timestamp']));
        } else {
          assert(result is shelf.Response);
          return _processCookieResult(result, tsid, tsidCookieIsNew, session,
              psid, request.context['timestamp']);
        }
      };

  Future<shelf.Response> _processCookieResult(
      shelf.Response response,
      String tsid,
      bool tsidCookieIsNew,
      LocalSessionData session,
      String psid,
      int timestamp) async {
    bool psidCookieIsNew = false;

    if (psid == null) {
      psid = session.psid;
      psidCookieIsNew = true;
    }

    var responseHeaders = {'Access-Control-Allow-Credentials': 'true'};

    var policy;
    final psidUri = Uri.parse('/a_la_carte/${Uri.encodeComponent(psid)}');
    if (response.context.containsKey('logout')) {
      final DateTime expires = new DateTime.fromMillisecondsSinceEpoch(0);
      responseHeaders['Set-Cookie'] = [];
      responseHeaders['Set-Cookie'] = [
        "TSID=; Expires=${HttpDate.format(expires)}; Path=/; HttpOnly",
        "PSID=; Path=/; Expires=${HttpDate.format(expires)}; HttpOnly"
      ];
    } else {
      if (tsidCookieIsNew) {
        responseHeaders['Set-Cookie'] = ["TSID=${tsid}; Path=/; HttpOnly"];
        if (!psidCookieIsNew) {
          _passivelyCreateSessionIdentityFromState(
              psid, session, timestamp, tsid);
        } else {
          final DateTime expires =
              new DateTime.now().add(new Duration(days: 15));
          responseHeaders['Set-Cookie'].add(
              "PSID=${psid}; Path=/; Expires=${HttpDate.format(expires)}; HttpOnly");
        }
      } else if (psidCookieIsNew) {
        final DateTime expires = new DateTime.now().add(new Duration(days: 15));
        responseHeaders['Set-Cookie'] = [
          "PSID=${psid}; Path=/; Expires=${HttpDate.format(expires)}; HttpOnly"
        ];
      }
    }
    session.refCount--;
    if (session.mustRecertify) {
      getOrCreateSessionListener(tsid, timestamp, psid);
    }
    return response.change(headers: responseHeaders);
  }

  Future _passivelyCreateSessionIdentityFromState(
      String psid, LocalSessionData session, int timestamp, String tsid) async {
    if (session.isAuthenticated == true) return session;
    if (session.isAuthenticated == false) return null;
    var sessionLock =
        await lockSessionForPassiveAuthentication(session, timestamp);
    if (sessionLock[0]) {
      var policy = await _authenticationModule.createPolicyIdentityFromState(
          session, _user, _dbConnection, timestamp);
      if (policy == null) {
        unlockSessionAfterPassiveAuthenticationFailed(session);
        return null;
      } else {
        await pushClientAuthorizationToMasterAfterAuthentication(
            session.tsid, timestamp, psid, policy);
        return session;
      }
    } else if (sessionLock[1]) {
      sessionUpdated(
          sessionLock[2],
          sessionLock[3],
          sessionLock[4],
          sessionLock[5],
          sessionLock[6],
          sessionLock[7],
          sessionLock[8],
          sessionLock[9],
          sessionLock[10]);
      return session;
    } else {
      return null;
    }
  }

  Future _activelyCreateSessionIdentityFromState(
      String psid,
      LocalSessionData session,
      int timestamp,
      String tsid,
      String code,
      String state) async {
    var sessionLock =
        await lockSessionForActiveAuthentication(session, timestamp);
    if (sessionLock[0]) {
      var policy = await _authenticationModule.createPolicyIdentityFromState(
          session, _user, _dbConnection, timestamp,
          code: code,
          notifyOnAuth: state,
          alsoCheckPassivePath: sessionLock[1]);
      if (policy == null) {
        unlockSessionAfterActiveAuthenticationFailed(session);
        return null;
      } else {
        await pushClientAuthorizationToMasterAfterAuthentication(
            session.tsid, timestamp, psid, policy);
        final originalDocumentIdAndRev = state.split(',');
        final originalDocumentId = originalDocumentIdAndRev[0];
        final originalDocumentRev = originalDocumentIdAndRev[1];
        new Future(() => _dbConnection.makeServiceDelete(
            Uri.parse('/a_la_carte/$originalDocumentId'), originalDocumentRev));
        return session;
      }
    } else if (sessionLock[1]) {
      sessionUpdated(
          sessionLock[2],
          sessionLock[3],
          sessionLock[4],
          sessionLock[5],
          sessionLock[6],
          sessionLock[7],
          sessionLock[8],
          sessionLock[9],
          sessionLock[10]);
      return session;
    } else {
      return null;
    }
  }

  bool _shouldCascade(shelf.Response response) {
    if (response.statusCode == _responseShouldCascade) return true;
    return false;
  }

  Future listen() async {
    final socket =
        await ServerSocket.bind(InternetAddress.ANY_IP_V4, _port, shared: true);
    assert(_authenticationModule != null);
    assert(_dbConnection != null);
    /* _dbConnection = new CouchDbBackend(
        couchPort, _user, _password, _policyModule, _debugOverWire); */

    var cascadeHandlers = new shelf.Cascade(shouldCascade: _shouldCascade)
        .add(_authLandingHandler)
        .add(_authLoginHandler)
        .add(_authSessionHandler)
        .add(_handleJsonRequest)
        .add(_handleStaticFileRequest);

    var handler = const shelf.Pipeline()
        .addMiddleware(_addTimestamp)
        .addMiddleware(shelf.logRequests())
        .addMiddleware(_addCookies)
        .addHandler(cascadeHandlers.handler);

    var server = new HttpServer.listenOn(socket);
    _logTopLevelErrors(server, handler);
    print('${new DateTime.now()}\tServing at http://'
        '${server.address.host}:${server.port}');
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

  dynamic _handleJsonRequest(shelf.Request request) {
    if (!_isJsonRequest(request)) {
      return new shelf.Response(_responseShouldCascade);
    }
    return request.hijack((input, output) => _dbHttpAdapter.hijackRequest(
        input,
        output,
        request.method,
        request.requestedUri,
        request.headers,
        request.context['tsid'],
        request.context['askForPushSession'],
        request.context['session'],
        request.context['timestamp']));
  }

  dynamic _authLandingHandler(shelf.Request request) async {
    if (request.url.path == '_auth/landing') {
      final LocalSessionData session = request.context['session'];
      var identity = await _activelyCreateSessionIdentityFromState(
          session.psid,
          session,
          request.context['timestamp'],
          session.tsid,
          request.requestedUri.queryParameters['code'],
          request.requestedUri.queryParameters['state']);
      if (identity != null) {
        return new shelf.Response.ok(_selfClosingPage,
            headers: {'Content-Type': 'text/html; charset=utf-8'});
      } else {
        return new shelf.Response(401,
            body: _errorPage(
                401, 'The code was not accepted by the token endpoint.'));
      }
    } else {
      return new shelf.Response(_responseShouldCascade);
    }
  }

  dynamic _authLoginHandler(shelf.Request request) async {
    if (request.url.path == '_auth/login') {
      final int timestamp = request.context['timestamp'];
      final LocalSessionData session = request.context['session'];
      await touchSession(session, timestamp);
      final policy = await _passivelyCreateSessionIdentityFromState(
          session.psid, session, timestamp, session.tsid);

      if (policy != null) {
        final response = new shelf.Response(200,
            body: '{"ok": true}',
            headers: {"Content-Type": "application/json"},
            encoding: Encoding.getByName('identity'));
        return response;
      } else {
        try {
          await _authenticationModule.prepareUnauthorizedRequest(
              _dbConnection, timestamp);
        } catch (error) {
          if (error is PolicyStateError) {
            if (error.redirectUri != null) {
              return new shelf.Response(401,
                  body:
                      '{"error": "must_authenticate", "message": "You must log in before '
                      'performing this action.", "auth_uri": "${error.redirectUri}", "auth_watcher_id": "${error.awakenId}", "auth_watcher_rev": "${error.awakenRev}"}',
                  headers: {"Content-Type": "application/json"},
                  encoding: Encoding.getByName('identity'));
            }
          }
          rethrow;
        }
      }
    } else {
      return new shelf.Response(_responseShouldCascade);
    }
  }

  dynamic _authSessionHandler(shelf.Request request) async {
    if (request.url.path == '_auth/session' && request.method == 'GET') {
      final int timestamp = request.context['timestamp'];
      final LocalSessionData session = request.context['session'];
      await touchSession(session, timestamp);
      await _passivelyCreateSessionIdentityFromState(
          session.psid, session, timestamp, session.tsid);

      String body = '''{
  "email": ${session.email == null ? 'null': '"' + session.email + '"'},
  "fullName": ${session.fullName == null ? 'null': '"' + session.fullName + '"'},
  "picture": ${session.picture == null ? 'null': '"' + session.picture + '"'}
}
''';
      return new shelf.Response.ok(body,
          headers: {'Content-Type': 'application/json'});
    } else if (request.url.path == '_auth/session' &&
        request.method == 'DELETE') {
      return new shelf.Response(201,
          headers: {'Content-Type': 'application/json'},
          context: {'logout': true});
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
        defaultHeaders['Keep-Alive'] = 'timeout=1200, max=32';
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
