library a_la_carte.server.db_backend;
import 'dart:async';

import 'shelf_utils.dart';

class ServiceError {
  final Map result;
  ServiceError(Map this.result);
}

abstract class DbBackend extends RequestHijacker {
  Future<Map> makeServiceGet(Uri uri);
  Future<Map> makeServicePut(Uri uri, Map message, [String revId = null]);
  Future makeServiceDelete(Uri uri, String revId);
}
