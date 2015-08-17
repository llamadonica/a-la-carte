part of a_la_carte.server;

class OAuth2DataStore {
  final String token;
  final String refreshToken;

  final Set<SendPort> sendPorts;

  DateTime whenToRefresh;
  DateTime lastRefreshed;
  Timer removeTimer;

  OAuth2DataStore(String this.token, DateTime this.whenToRefresh)
  : sendPorts = new HashSet<SendPort>();
}
