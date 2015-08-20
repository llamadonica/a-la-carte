part of a_la_carte.server;

class ServiceError {
  final Map result;
  ServiceError(Map this.result);
}

abstract class DbBackend {
  Future<Map> makeServiceGet(Uri uri);
  Future<Map> makeServicePut(Uri uri, Map message, [String revId = null]);
  Future makeServiceDelete(Uri uri, String revId);
}
