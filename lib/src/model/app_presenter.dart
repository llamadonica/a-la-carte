part of a_la_carte_models;

enum ErrorReportModule {
  projectSaver
}

typedef void JsonEventRouter(
    JsonStreamingEvent event, Ref<StreamSubscription> subscription);


abstract class Presenter {
  void setUrl(String url, String title);
  Stream<List<String>> get onExternalNavigationEvent;

  void reportError(ErrorReportModule module, String message);
  Future<int> nextJobNumber(int year);

  Future<Project> ensureProjectIsLoaded(String uuid);
  Future<String> getServiceAccountName();

  void connectTo(String uri, JsonEventRouter router, {bool isImplicitArray: false});
  void showAuthLogin(String uri);
}
