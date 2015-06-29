part of dgs.models;

class ContactInfo extends ChangeNotifier implements JsonIInit, JsonIGet {
  @observable String name;
  @observable ObservableList<ObservablePair> contactItems;
  Map<ObservablePair, StreamSubscription> _changeSubscriptions = new Map();

  Map _json = {};

  Map _jsonOld = {};

  @override
  get json => _json;

  @override
  void initFromJSON(dynamic values) {
    _json = values;

    name = (values != null &&
        values is Map &&
        values.isNotEmpty &&
        values['contactItems'] != null) ?
        values['name'] :
        '';
    contactItems = new ObservableList();
    if (values != null &&
        values is Map &&
        values.isNotEmpty &&
        values['contactItems'] != null) for (var item in values['contactItems']) {
      var newContactInfo = new ObservablePair();
      newContactInfo.initFromJSON(item);
      _changeSubscriptions[newContactInfo] = newContactInfo.changes.listen(
          _contactItemChangeHandler);
      contactItems.add(newContactInfo);
    }
    changes.listen((changes) {
      bool changeIsValid = false;
      for (var change in changes) if (change is PropertyChangeRecord &&
          change.name != #json &&
          change.name != #isSynced) changeIsValid = true;
      if (changeIsValid) notifyPropertyChange(
          #json,
          _jsonOld = _json,
          _json = _jsonGetter());
    });
    contactItems.listChanges.listen((changes) {
      bool changeIsValid = false;
      for (ListChangeRecord change in changes) {
        for (var removedContactItem in change.removed) {
          _changeSubscriptions[removedContactItem].cancel();
          changeIsValid = true;
        }
        if (change.addedCount > 0) {
          for (var i =
              change.index; i < change.index + change.addedCount; i++) {
            _changeSubscriptions[contactItems[i]] =
                contactItems[i].changes.listen(
                _contactItemChangeHandler);
          }
          changeIsValid = true;
        }
      }
      if (changeIsValid) notifyPropertyChange(
          #json,
          _jsonOld = _json,
          _json = _jsonGetter());
    });
  }

  _contactItemChangeHandler(changes) {
    bool changeIsValid = false;
    for (var change in changes) {
      if (change is PropertyChangeRecord &&
          change.name != #json) changeIsValid = true;
    }
    if (changeIsValid) notifyPropertyChange(
        #json,
        _jsonOld = _json,
        _json = _jsonGetter());
  }

  Map _jsonGetter() {
    var values = {};
    values['name'] = name;
    values['contactItems'] = [];
    for (var contactItem in contactItems) values['contactItems'].add(
        contactItem.json);
    return values;
  }
}
