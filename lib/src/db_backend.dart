library a_la_carte.server.db_backend;

import 'dart:async';

import 'shelf_utils.dart';

class DbServiceError {
  final Map result;
  DbServiceError(Map this.result);
}

abstract class DbBackend {
  Future<Map> makeServiceGet(Uri uri);
  Future<Map> makeServicePut(Uri uri, Map message, [String revId = null]);
  Future makeServiceDelete(Uri uri, String revId);
}
