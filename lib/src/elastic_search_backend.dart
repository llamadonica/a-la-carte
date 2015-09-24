library a_la_carte.server.elastic_search_backend;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:d17/d17.dart';

import 'search_backend.dart';

class ElasticSearchServiceError extends SearchServiceError {
  ElasticSearchServiceError(Map result) : super(result);
}

class ElasticSearchBackend extends SearchBackend {
  @inject HttpClient _httpClient;

  final int port;

  @Inject(name: 'a_la_carte.server.debugOverWire')
  bool debugOverWire;

  @inject
  ElasticSearchBackend(
      @Named('a_la_carte.server.couch_db_backend.elasticSearchPort') int this.port);

  Future<Map> makeServiceSearch(String type, Map<String, String> queryParts) async {
    StringBuffer q = new StringBuffer();
    q.writeAll(queryParts.keys.map((key) => key + ':' + queryParts[key]), '%20');
    final elasticUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: [type, '_search'],
        queryParameters: {'q': q.toString()});
    final HttpClientRequest request = await _httpClient.openUrl('GET', elasticUri);
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
      throw new ElasticSearchServiceError(map);
    }
  }

  Future updatesToIndex(List<Map> documents) async {
    final elasticUri = new Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        pathSegments: [ '_bulk']);
    final HttpClientRequest request = await _httpClient.openUrl('PUT', elasticUri);

    final List<int> encodedMessage = new List();

    final jsonEncoder = new JsonEncoder().fuse(new Utf8Encoder());
    for (var document in documents) {
      var tempDocument = new Map();
      tempDocument['_type'] = document['type'];
      tempDocument['_index'] = 'a_la_carte';
      tempDocument['_id'] = document['_id'];
      encodedMessage.addAll(jsonEncoder.convert(tempDocument));
      encodedMessage.add(10);
      encodedMessage.addAll(jsonEncoder.convert(document));
    }
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
      throw new ElasticSearchServiceError(map);
    }
  }
}
