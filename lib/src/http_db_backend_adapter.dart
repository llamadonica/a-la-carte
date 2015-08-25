library a_la_carte.server.http_db_backend_adapter;

import 'db_backend.dart';

class HttpDbBackendAdapter<T extends DbBackend> {
  Future hijackRequest(
      Stream<List<int>> input,
      StreamSink<List<int>> output,
      String method,
      Uri uri,
      Map<String, Object> headers,
      String tsid,
      bool canGetSessionData,
      LocalSessionData session);
}


