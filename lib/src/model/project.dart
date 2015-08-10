part of a_la_carte_models;

class Project extends JsonCanSync {
  final String id;

  bool committed = false;
  bool isChanged = false;

  @observable String name;
  String _oldName;
  @observable int jobNumber;
  @observable bool isActive;
  @observable String initials;
  @observable String streetAddress;

  Map _json = {};
  Project(String this.id);
  Map get json => _json;

  void initFromJSON(Map values) {
    _json = values;

    _oldName = name = values['name'];
    jobNumber = values['jobNumber'];
    initials = values['initials'];
    streetAddress = values['streetAddress'];
  }

  void resetToSavedState() {
    initFromJSON(_json);
  }

  Map jsonGetter() => {
    'name': name,
    'jobNumber': jobNumber,
    'initials': initials,
    'streetAddress': streetAddress
  };
}
