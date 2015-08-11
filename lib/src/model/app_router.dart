part of a_la_carte_models;

enum ErrorReportModule {
  projectSaver
}

abstract class AppRouter {
  void setUrl(String url, String title);
  Stream<List<String>> get onAppNavigationEvent;

  void reportError(ErrorReportModule module, String message);
  Future<int> nextJobNumber(int year);
}
