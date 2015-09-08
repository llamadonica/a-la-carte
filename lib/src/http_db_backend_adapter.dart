library a_la_carte.server.http_db_backend_adapter;

import 'dart:async';
import 'local_session_data.dart';

abstract class HttpDbBackendAdapter {
  Future hijackRequest(
      Stream<List<int>> input,
      StreamSink<List<int>> output,
      String method,
      Uri uri,
      Map<String, Object> headers,
      String tsid,
      bool canGetSessionData,
      LocalSessionData session,
      int timestamp);
}
