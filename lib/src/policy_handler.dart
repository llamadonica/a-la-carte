part of a_la_carte.server;

abstract class PolicyIdentity {
  String get id;
}

abstract class PolicyHandler extends Object {
  Future validateMethodIsPermittedOnResource(String method, Uri uri,
                                             PolicyIdentity identity, CouchDataStoreAbstraction dataStore);
  Future convoluteUnchunkedRequest(
      HttpClientRequest request, PolicyIdentity identity, String addCookie);
  Future convoluteChunkedRequest(
      HttpClientRequest request, PolicyIdentity identity, String addCookie);

  Future hijackUnauthorizedMethod(Stream<List<int>> input,
                                  StreamSink<List<int>> output, String method, Uri uri,
      Map<String, Object> headers);
}
