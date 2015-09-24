library a_la_carte.server.search_backend;

import 'dart:async';

class SearchServiceError {
  final Map result;
  SearchServiceError(Map this.result);
}

abstract class SearchBackend {
  Future<Map> makeServiceSearch(String type, Map<String, String> queryParts);
  Future updatesToIndex(List<Map> documents);
}
