library a_la_carte.server.http_couch_db_backend_adapter;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:d17/d17.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'local_session_data.dart';
import 'http_db_backend_adapter.dart';
import 'couch_db_backend.dart';
import 'ref.dart';
import 'authenticator.dart';
import 'logger.dart';
import 'shelf_utils.dart';

class HttpCouchDbBackendAdapter implements HttpDbBackendAdapter {
  @from CouchDbBackend _dbConnection;

  @inject Authenticator _policyHandler;

  @inject HttpClient _httpClient;

  @inject Logger defaultLogger;

  @Inject(name: 'a_la_carte.server.debugOverWire')
  bool _debugOverWire;

  Future hijackRequest(
      Stream<List<int>> input,
      StreamSink<List<int>> output,
      String method,
      Uri uri,
      Map<String, Object> headers,
      String tsid,
      bool canGetSessionData,
      LocalSessionData session,
      int timestamp) async {
    final couchUri = new Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: '127.0.0.1',
        port: _dbConnection.port,
        pathSegments: uri.pathSegments,
        queryParameters: uri.queryParameters,
        fragment: uri.fragment);
    await _dbConnection.ensureHasValidated();
    try {
      try {
        await _policyHandler.validateMethodIsPermittedOnResource(
            method, uri, _dbConnection, session, timestamp);
      } catch (error) {
        var contentLength = new Ref<int>();
        var postRequestIsChunked = false;
        if (headers.containsKey('Transfer-Encoding') &&
            headers['Transfer-Encoding'] == 'chunked') {
          postRequestIsChunked = true;
        } else {
          try {
            contentLength.value = int.parse(headers['Content-Length']);
          } catch (err) {}
        }
        final completer = new Completer();
        if (method == 'GET' || method == 'HEAD' || method == 'DELETE') {
          completer.complete();
        } else {
          input.listen((data) {
            if (postRequestIsChunked && data.length == 0) {
            } else if (!postRequestIsChunked) {
              contentLength.value -= data.length;
              if (contentLength.value <= 0) {
                completer.complete();
              }
            }
          });
        }
        await completer.future;
        rethrow;
      }
      HttpClientRequest request = await _httpClient.openUrl(method, couchUri);
      var modifiableHeaders = new Map.from(headers);
      var extraData = {'timestamp': new DateTime.now().millisecondsSinceEpoch};
      final innerRequest = await _policyHandler.convoluteRequest(
          modifiableHeaders, input, session, extraData);
      for (var header in modifiableHeaders.keys) {
        request.headers.add(header, modifiableHeaders[header]);
      }
      for (var cookie in _dbConnection.authCookie) {
        request.headers.add(HttpHeaders.COOKIE, cookie);
      }
      bool postRequestIsChunked = false;
      var contentLength = new Ref<int>.withValue(0);

      if (method == 'GET' || method == 'HEAD' || method == 'DELETE') {
        request.close();
      } else if (headers.containsKey('Transfer-Encoding') &&
          headers['Transfer-Encoding'] == 'chunked') {
        postRequestIsChunked = true;
      } else {
        try {
          contentLength.value = int.parse(headers['Content-Length']);
        } catch (err) {
          request.close();
        }
      }
      innerRequest.listen((data) {
        request.add(data);
        if (postRequestIsChunked && data.length == 0) {
          request.close();
        } else if (!postRequestIsChunked) {
          contentLength.value -= data.length;
          if (contentLength.value <= 0) {
            request.close();
          }
        }
      }, onDone: () {
        request.close();
      });
      HttpClientResponse response = await request.done;
      final encoder = new AsciiEncoder();
      output.add(encoder.convert(
          'HTTP/1.1 ${response.statusCode} ${response.reasonPhrase}\r\n'));
      response.headers.forEach((headerName, headerValues) {
        for (var headerValue in headerValues) {
          if (headerName.toLowerCase() != 'set-cookie') {
//Authentication cookies don't need to be leaked to the end user,
//even though it's not clear what they would do with it.
            output.add(encoder.convert('$headerName: $headerValue\r\n'));
          }
        }
      });
      bool chunkedResponse = false;
      chunkedResponse = response.headers.chunkedTransferEncoding;
      output.add(encoder.convert('Access-Control-Allow-Origin: *\r\n'));

      if (canGetSessionData) {
        if (session.isAuthenticated) {
          output.add(encoder.convert(
              'Access-Control-Allow-Headers: X-Push-Session-Data\r\n'));
          output
              .add(encoder.convert('X-Push-Session-Data: /_auth/session\r\n'));
        }
      }
      output.add([13, 10]);
      response.listen((data) {
        if (chunkedResponse) {
          output.add(encoder.convert('${data.length.toRadixString(16)}\r\n'));
        }
        output.add(data);
        if (chunkedResponse) {
          output.add([13, 10]);
        }
      }, onDone: () {
        if (chunkedResponse) {
          output.add([48, 13, 10, 13, 10]);
        } else {}
        output.close();
      }, onError: (error, stackTrace) {
        output.addError(error, stackTrace);
      });
    } catch (error, stackTrace) {
      if (error is PolicyStateError) {
        shelf.Response response;
        if (error.redirectUri != null) {
          response = new shelf.Response(401,
              body:
                  '{"error": "must_authenticate", "message": "You must log in before '
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
        await writeShelfResponse(output, response);
        return;
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
  "dart_error": ${encoder.convert(error_info)}
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
        await writeShelfResponse(output, response);
        return;
      }
    }
  }
}
