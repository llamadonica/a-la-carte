library a_la_carte.server.http_search_backend_adapter;

import 'dart:async';

abstract class HttpSearchBackendAdapter {
  Future hijackRequest(
      Stream<List<int>> input,
      StreamSink<List<int>> output,
      String method,
      Uri uri,
      Map<String, Object> headers);
  Future doOccassionalCleanup();
}
