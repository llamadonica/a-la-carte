part of a_la_carte.server;

class OAuth2DataStore {
  final String uuid;
  final Set<SendPort> sendPorts;
  DateTime expires;
  DateTime lastRefreshed;
  Timer removeTimer;

  OAuth2DataStore(String this.uuid, DateTime this.expires)
  : sendPorts = new HashSet<SendPort>();
}
