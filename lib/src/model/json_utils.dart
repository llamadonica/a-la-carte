part of a_la_carte_models;

abstract class JsonCanSync extends ChangeNotifier
    implements JsonIInit, JsonIGet {
  final Ref<int> refCount = new Ref<int>.withValue(0);
  @published bool isSynced = true;
  String get id;
}

abstract class JsonIGet {
  dynamic get json;
}

abstract class JsonIInit {
  void initFromJSON(dynamic values);
}
