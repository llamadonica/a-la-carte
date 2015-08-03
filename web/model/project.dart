part of a_la_carte_models;



class Project extends JsonCanSync {
  final String id;
  
  bool commited = false;

  @observable String name;
  String _oldName;
  @observable int jobNumber;
  @observable bool isActive;
  @observable String initials;
  @observable String streetAddress;

  Map _jsonOld = {};

  Map _json = {};
  Project(String this.id);
  Map get json => _json;

  void initFromJSON(Map values) {
    _json = values;

    _oldName = name = values['name'];
    jobNumber = values['jobNumber'];
    initials = values['initials'];
    streetAddress = values['streetAddress'];

    changes.listen((changes) {
      bool changeIsValid = false;
      for (var change in changes) {
        if (change.name == #name) {
          var tempOldName = _oldName;
          nameChanged(tempOldName);
          if (name != tempOldName) {
            changeIsValid = true;
          }
        }
        else if (change is PropertyChangeRecord &&
            change.name != #json &&
            change.name != #isSynced) changeIsValid = true;

      }
      if (changeIsValid) {
        notifyPropertyChange(#json, _jsonOld = _json, _json = _jsonGetter());
      }
    });
  }
  
  void nameChanged(String oldValue) {
    if (commited && oldValue != null) {
      var allSpaces = new RegExp(r'''^\s*$''');
      if (allSpaces.hasMatch(name) && !allSpaces.hasMatch(oldValue)) {
        _oldName = name;
        name = oldValue;
        return;
      }
    }
    _oldName = name;
  }

  Map _jsonGetter() => {
    'name': name,
    'jobNumber': jobNumber,
    'initials': initials,
    'streetAddress': streetAddress
  };
}
