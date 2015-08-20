// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

part of a_la_carte.server;

class Ref<T> {
  T value;
  Ref();
  Ref.withValue(T this.value);
}

class CouchError extends ServiceError {
  CouchError(Map result) : super(result);
}

class CouchDbBackend extends DbBackend {
  final int port;
  final String _user;
  final String _password;
  final PolicyValidator policyHandler;
  final bool _debugOverWire;

  List<String> _authCookie = null;
  bool hasValidated = false;
  Future _ensuringHasValidated;

  CouchDbBackend(int this.port, String this._user, String this._password,
      PolicyValidator this.policyHandler, bool this._debugOverWire);

  _validateSession() {
    final client = new HttpClient();
    final couchUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: ['_session']);
    return client.openUrl('POST', couchUri).then((request) {
      String requestBody = JSON.encode({'name': _user, 'password': _password});
      request.headers.add(HttpHeaders.HOST, 'localhost:5984');
      request.headers.add(HttpHeaders.ACCEPT, 'application/json');
      request.headers.add(HttpHeaders.CONTENT_TYPE, 'application/json');
      request.headers.add(HttpHeaders.CONTENT_LENGTH, requestBody.length);
      request.add(ASCII.encode(requestBody));
      return request.close();
    }).then((HttpClientResponse response) {
      final setCookie = response.headers[HttpHeaders.SET_COOKIE];
      if (response.statusCode == 200 && setCookie != null) {
        _authCookie = new List<String>();
        if (setCookie is String) {
          _authCookie.add(setCookie.split(';')[0]);
        } else {
          assert(setCookie is List);
          for (var setCookiePart in setCookie) {
            _authCookie.add(setCookiePart.split(';')[0]);
          }
          hasValidated = true;
          return null;
        }
      } else {
        var contentLength = new Ref<int>.withValue(
            int.parse(response.headers[HttpHeaders.CONTENT_LENGTH][0]));
        List<int> content = new List<int>();
        return response.asyncMap((inputList) {
          if (contentLength.value <= 0) {
            return null;
          }
          content.addAll(inputList);
          contentLength.value -= inputList.length;
          return null;
        }).last.then((_) {
          throw new StateError(new Utf8Codec().decode(content));
        });
      }
    });
  }

  Future _ensureHasValidated() {
    if (hasValidated) return new Future.value();
    else if (_ensuringHasValidated == null) {
      _ensuringHasValidated = _validateSession().then((_) {
        final interval = new Duration(minutes: 9);
        new Timer.periodic(interval, (_) => _validateSession());
      });
    }
    return _ensuringHasValidated;
  }

  Future hijackRequest(Stream<List<int>> input, StreamSink<List<int>> output,
      String method, Uri uri, Map<String, Object> headers) async {
    final client = new HttpClient();
    final couchUri = new Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: '127.0.0.1',
        port: port,
        pathSegments: uri.pathSegments,
        queryParameters: uri.queryParameters,
        fragment: uri.fragment);
    await _ensureHasValidated();
    try {
      policyHandler.validateMethodIsPermittedOnResource(method, uri, this);
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
      input.listen((data) {
        if (postRequestIsChunked && data.length == 0) {
        } else if (!postRequestIsChunked) {
          contentLength.value -= data.length;
          if (contentLength.value <= 0) {
            completer.complete();
          }
        }
      });
      await completer.future;
      throw error;
    }
    HttpClientRequest request = await client.openUrl(method, couchUri);
    for (var header in headers.keys) {
      request.headers.add(header, headers[header]);
    }
    for (var cookie in _authCookie) {
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
    input.listen((data) {
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
    try {
      final encoder = new AsciiEncoder();
      output.add(encoder.convert(
          'HTTP/1.1 ${response.statusCode} ${response.reasonPhrase}\r\n'));
      response.headers.forEach((headerName, headerValues) {
        for (var headerValue in headerValues) {
          output.add(encoder.convert('$headerName: $headerValue\r\n'));
        }
      });
      bool chunkedResponse = false;
      chunkedResponse = response.headers.chunkedTransferEncoding;
      output.add(encoder.convert('Access-Control-Allow-Origin: *\r\n'));
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
              body: '{"error": "must_authenticate", "message": "You must log in before '
              'performing this action.", "auth_uri": "${error.redirectUri}", "auth_watcher": "${error.awakenUuid}"}',
              headers: {"Content-Type": "application/json"},
              encoding: Encoding.getByName('identity'));
        } else {
          final encoder = new JsonEncoder();
          response = new shelf.Response.internalServerError(
              body: encoder.convert(error.replyFromDbBackend),
              headers: {"Content-Type": "application/json"},
              encoding: Encoding.getByName('identity'));
        }
        await _writeShelfResponse(output, response);
        return;
      } else {
        String body;
        if (_debugOverWire) {
          body = '''{
  "error":"internal_server_error",
  "message": "I couldn\'t connect to the database. Contact your database administrator.",
  "dart_error": "$error",
  "dart_stacktrace": "$stackTrace"
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
        await _writeShelfResponse(output, response);
        return;
      }
    }
  }

  @override Future<Map> makeServiceGet(Uri uri) async {
    final client = new HttpClient();
    final couchUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: uri.pathSegments,
        queryParameters: uri.queryParameters,
        fragment: uri.fragment);
    await _ensureHasValidated();
    final HttpClientRequest request = await client.openUrl('GET', couchUri);
    for (var cookie in _authCookie) {
      request.headers.add(HttpHeaders.COOKIE, cookie);
    }
    final HttpClientResponse response = await request.close();
    final data = await response.toList();
    final utfDecoder = new Utf8Decoder();
    final statusCode = response.statusCode;
    final json = utfDecoder.convert(new List.from(data.expand((e) => e)));
    final jsonDecoder = new JsonDecoder();
    final map = jsonDecoder.convert(json);
    if (statusCode >= 200 && statusCode < 300) {
      return map;
    } else {
      throw new CouchError(map);
    }
  }

  @override
  Future<Map> makeServicePut(Uri uri, Map message,
      [String revId = null]) async {
    final client = new HttpClient();
    final couchUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: uri.pathSegments,
        queryParameters: uri.queryParameters,
        fragment: uri.fragment);
    await _ensureHasValidated();
    final HttpClientRequest request = await client.openUrl('PUT', couchUri);
    for (var cookie in _authCookie) {
      request.headers.add(HttpHeaders.COOKIE, cookie);
    }
    final jsonEncoder = new JsonEncoder().fuse(new Utf8Encoder());
    final List<int> encodedMessage = jsonEncoder.convert(message);
    request.headers
      ..add(HttpHeaders.CONTENT_LENGTH, encodedMessage.length.toString())
      ..add(HttpHeaders.CONTENT_TYPE, 'application/json');
    request.add(encodedMessage);
    final HttpClientResponse response = await request.close();
    final data = await response.toList();
    final utfDecoder = new Utf8Decoder();
    final statusCode = response.statusCode;
    final json = utfDecoder.convert(new List.from(data.expand((e) => e)));
    final jsonDecoder = new JsonDecoder();
    final map = jsonDecoder.convert(json);
    if (statusCode >= 200 && statusCode < 300) {
      return map;
    } else {
      throw new CouchError(map);
    }
  }

  @override Future<Map> makeServiceDelete(Uri uri, String revId) async {
    final client = new HttpClient();
    final queryParameters = new Map.from(uri.queryParameters);
    queryParameters['rev'] = revId;
    final couchUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: uri.pathSegments,
        queryParameters: queryParameters,
        fragment: uri.fragment);
    await _ensureHasValidated();
    HttpClientRequest request = await client.openUrl('DELETE', couchUri);
    for (var cookie in _authCookie) {
      request.headers.add(HttpHeaders.COOKIE, cookie);
    }
    request.headers.add(HttpHeaders.CONTENT_TYPE, 'application/json');
    final HttpClientResponse response = await request.close();
    final data = await response.toList();
    final utfDecoder = new Utf8Decoder();
    final statusCode = response.statusCode;
    final json = utfDecoder.convert(new List.from(data.expand((e) => e)));
    final jsonDecoder = new JsonDecoder();
    final map = jsonDecoder.convert(json);
    if (statusCode >= 200 && statusCode < 300) {
      return map;
    } else {
      throw new CouchError(map);
    }
  }
}
