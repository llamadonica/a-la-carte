// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library a_la_carte.server.couch_db_backend;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:json_stream_parser/json_stream_parser.dart';
import 'package:d17/d17.dart';

import 'db_backend.dart';
import 'ref.dart';

class CouchError extends DbServiceError {
  CouchError(Map result) : super(result);
}

class CouchDbBackend extends DbBackend {
  List<String> _authCookie = null;
  List<String> get authCookie => new List.unmodifiable(_authCookie);
  bool _hasValidated = false;
  Future _ensuringHasValidated;

  @inject HttpClient _httpClient;

  final int port;

  @Inject(name: 'a_la_carte.server.couch_db_backend.couchDbUser')
  String _user;

  @Inject(name: 'a_la_carte.server.couch_db_backend.couchDbPassword')
  String _password;

  @Inject(name: 'a_la_carte.server.debugOverWire')
  bool debugOverWire;

  @inject
  CouchDbBackend(
      @Named('a_la_carte.server.couch_db_backend.couchDbPort') int this.port);

  Future _validateSession() async {
    final couchUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: ['_session']);
    var request = await _httpClient.openUrl('POST', couchUri);
    String requestBody = JSON.encode({'name': _user, 'password': _password});
    request.headers.add(HttpHeaders.HOST, 'localhost:5984');
    request.headers.add(HttpHeaders.ACCEPT, 'application/json');
    request.headers.add(HttpHeaders.CONTENT_TYPE, 'application/json');
    request.headers.add(HttpHeaders.CONTENT_LENGTH, requestBody.length);
    request.add(ASCII.encode(requestBody));
    HttpClientResponse response = await request.close();
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
        _hasValidated = true;
        return null;
      }
    } else {
      var contentLength = new Ref<int>.withValue(
          int.parse(response.headers[HttpHeaders.CONTENT_LENGTH][0]));
      List<int> content = new List<int>();
      await for (var inputList in response) {
        if (contentLength.value <= 0) {
          return null;
        }
        content.addAll(inputList);
        contentLength.value -= inputList.length;
        return null;
      }
      throw new StateError(new Utf8Codec().decode(content));
    }
  }

  Future ensureHasValidated() {
    if (_hasValidated) return new Future.value();
    else if (_ensuringHasValidated == null) {
      _ensuringHasValidated = _validateSession().then((_) {
        final interval = new Duration(minutes: 9);
        new Timer.periodic(interval, (_) => _validateSession());
      });
    }
    return _ensuringHasValidated;
  }

  @override Future<Map> makeServiceGet(Uri uri) async {
    final couchUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: uri.pathSegments,
        queryParameters: uri.queryParameters,
        fragment: uri.fragment);
    await ensureHasValidated();
    final HttpClientRequest request =
        await _httpClient.openUrl('GET', couchUri);
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
    final couchUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: uri.pathSegments,
        queryParameters: uri.queryParameters,
        fragment: uri.fragment);
    await ensureHasValidated();
    final HttpClientRequest request =
        await _httpClient.openUrl('PUT', couchUri);
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
    final queryParameters = new Map.from(uri.queryParameters);
    queryParameters['rev'] = revId;
    final couchUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: uri.pathSegments,
        queryParameters: queryParameters,
        fragment: uri.fragment);
    await ensureHasValidated();
    HttpClientRequest request = await _httpClient.openUrl('DELETE', couchUri);
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

  @override
  Stream<Map> subscribeToChanges(String schema, [int since]) async* {
    Stream<Map> subscribeToChangesInternal([int since]) async* {
      var queryParameters = {
        'feed': 'continuous',
        'include_docs': 'true',
        'filter': 'projects/projects',
        'account': _user
      };
      if (since != null) {
        queryParameters['since'] = since.toString();
      }
      final couchUri = new Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: port,
          pathSegments: [schema, '_changes'],
          queryParameters: queryParameters);
      await ensureHasValidated();
      HttpClientRequest request = await _httpClient.openUrl('GET', couchUri);
      for (var cookie in _authCookie) {
        request.headers.add(HttpHeaders.COOKIE, cookie);
      }
      request.headers.add(HttpHeaders.CONTENT_TYPE, 'application/json');
      final HttpClientResponse response = await request.close();
      bool chunkedResponse = false;
      chunkedResponse = response.headers.chunkedTransferEncoding;

      yield* response
      .expand((t) => t)
      .transform(new JsonStreamTransformer(true))
      .transform(new StreamTransformer(_transformToMap));
    }
    int currentChange = since;
    while (true) {
      await for (var currentChangeMap in subscribeToChangesInternal(currentChange)) {
        if (currentChangeMap.containsKey('seq')) {
          currentChange = currentChangeMap['seq'];
          yield currentChangeMap;
        } else if (currentChangeMap.containsKey('last_seq')) {
          currentChange = currentChangeMap['last_seq'];
        }
      }
    }
  }

  StreamSubscription _transformToMap(Stream<JsonStreamingEvent> stream, bool cancelOnError) {
    Stream<Map> _transformToMapInternal() async* {
      await for (JsonStreamingEvent event in stream) {
        if (event.eventType == JsonStreamingEventType.close && event.path.length == 1) {
          yield event.symbol;
        }
      }
    }
    return _transformToMapInternal().listen(null);
  }
}



Future<List> couchDbRetrievePermissions(
    DbBackend backend_, String email, String permissionPath,
    [state]) async {
  assert(backend_ is CouchDbBackend);
  CouchDbBackend backend = backend_;
  final couchUri = new Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: backend.port,
      path: permissionPath);
  Map allAuthenticationData = await backend.makeServiceGet(couchUri);
  Map allNames = allAuthenticationData['names'];
  if (!allNames.containsKey(email)) {
    return [];
  }
  return allNames[email]['a_la_carte_roles'];
}
