part of a_la_carte_models;

abstract class AppRouter {
  void setUrl(String url, String title);
  Stream<List<String>> get onAppNavigationEvent;
}
