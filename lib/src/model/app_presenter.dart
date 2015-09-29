part of a_la_carte_models;

enum ErrorReportModule { projectSaver, login }

typedef void JsonEventRouter(
    HttpResponseJsonStreamingEvent event, Ref<StreamSubscription> subscription);

abstract class Presenter {
  void setUrl(String url, String title);
  Stream<List<String>> get onExternalNavigationEvent;

  void reportError(ErrorReportModule module, String message);
  Future<int> nextJobNumber(int year);

  Future<Project> ensureProjectIsLoaded(String uuid);
  Future<String> getServiceAccountName();

  void connectTo(String uri, JsonEventRouter router,
      {bool isImplicitArray: false, String method: 'GET'});
  void showAuthLogin(String uri);
  void receiveAuthenticationSessionData();
  void clearAuthenticationSessionData();
  void goToDefault();
}
