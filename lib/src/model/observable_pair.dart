part of a_la_carte_models;

class ObservablePair extends ChangeNotifier implements JsonIInit, JsonIGet {
  @observable String first;
  @observable String second;
  @observable bool isNew = true;
  Map _json = {};
  Map _jsonOld = {};

  @override Map get json => _json;
  @override void initFromJSON(values) {
    first = values['first'];
    second = values['second'];
    isNew = false;
    _json = _jsonGetter();

    changes.listen((changes) {
      bool changeIsValid = false;
      for (var change in changes) {
        if (change is PropertyChangeRecord && change.name != #json) {
          changeIsValid = true;
        }
      }
      if (changeIsValid) {
        notifyPropertyChange(#json, _jsonOld = _json, _json = _jsonGetter());
      }
    });
  }

  Map _jsonGetter() => {'first': first, 'second': second};
}
