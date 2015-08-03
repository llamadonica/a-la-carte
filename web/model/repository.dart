part of a_la_carte_models;

class Repository extends JsonCanSync {
  final AppDelegate _appDelegate;
  List<String> _jsonOld;

  ObservableList<String> _json;

  Repository(AppDelegate this._appDelegate) {
    if (_appDelegate.refCount++ >
        0) throw new StateError("Only one Repository per app is supported.");
  }

  String get id => '_REPOSITORY_';
  get json => _json;

  List<String> get projectIds => new List.from(_json);

  void addProject(Project project) {
    _appDelegate.writeJson(project.id, project.json);
    _json.add(project.id);
  }

  Future<Project> getProject(String id) {
    var project = new Project(id);
    return _appDelegate.getEntity(id, project).then((project) {
      project.commited = true;
      return project;
    });
  }

  void initFromJSON(values) {
    if (values is Map && values.isEmpty) {
      _json = new ObservableList();
    } else {
      _json = new ObservableList.from(values);
    }
    _jsonOld = null;
    _json.changes.listen((_) {
      notifyPropertyChange(#json, _jsonOld, _json);
      _jsonOld = new List.from(_json);
    });
  }
}
