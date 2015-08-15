part of a_la_carte_models;

typedef int Comparator<T>(T a, T b);

class Project extends JsonCanSync {
  final String id;

  bool committed = false;
  bool _isChanged = false;

  bool get isChanged => _isChanged;

  void set isChanged(bool value) {
    _isChanged = value;
    if (!value) _locallyChangedSymbols.clear();
  }

  Set<Symbol> _locallyChangedSymbols = new Set<Symbol>();

  @observable String name;
  String _oldName;
  @observable num jobNumber;
  @observable bool isActive;
  @observable String initials;
  @observable String streetAddress;
  @observable String serviceAccountName;

  String rev;

  int _jobNumberInPresortedList;
  int get jobNumberInPresortedList => _jobNumberInPresortedList;

  Map _json = {};
  Project(String this.id);
  Map get json => _json;

  static insertIntoPresortedList(Project project, List<Project> projects,
      [Comparator comparison = null]) {
    if (comparison == null) {
      comparison = _compareProjectsForInsert;
    }
    int projectsMax = projects.length;
    var projectsMin = 0;
    var projectsDelta = (projectsMax >> 1);
    while (projectsDelta > 0) {
      final compareProject = projects[projectsMin + projectsDelta];
      if (comparison(project, compareProject) > 0) {
        projectsMin += projectsDelta;
        projectsDelta = projectsMax - projectsMin;
      } else {
        projectsMax = projectsMin + projectsDelta;
      }
      projectsDelta >>= 1;
    }
    var offset = (projectsMin == 0 &&
        comparison(project, projects[projectsMin]) <= 0) ? 0 : 1;
    projects.insert(projectsMin + offset, project);
    project._jobNumberInPresortedList = project.jobNumber;
  }
  static void removeFromPresortedList(List<Project> projects, Project project,
      [Comparator comparison = null]) {
    if (comparison == null) {
      comparison = _compareProjectsForRemove;
    }
    int projectsMax = projects.length;
    var projectsMin = 0;
    var projectsDelta = (projectsMax >> 1);
    while (projectsDelta > 0) {
      final compareProject = projects[projectsMin + projectsDelta];
      final compareResult = comparison(project, compareProject);
      if (compareResult == 0) {
        projects.removeAt(projectsMin + projectsDelta);
        project._jobNumberInPresortedList = null;
        return;
      } else if (comparison(project, compareProject) > 0) {
        projectsMin += projectsDelta;
        projectsDelta = projectsMax - projectsMin;
      } else {
        projectsMax = projectsMin + projectsDelta;
      }
      projectsDelta >>= 1;
    }
    if (projectsMin == 0 && comparison(project, projects[0]) == 0) {
      projects.removeAt(0);
      project._jobNumberInPresortedList = null;
      return;
    }
    throw new ArgumentError('$project was not in the projects list.');
  }

  static void repositionInPresortedList(List<Project> projects, Project project,
      [Comparator comparison = null]) {
    removeFromPresortedList(projects, project, comparison);
    insertIntoPresortedList(project, projects, comparison);
  }


  static _compareProjectsForInsert(Project a, Project b) {
    var jobNumberSort = b._jobNumberInPresortedList - a.jobNumber;
    return (jobNumberSort == 0) ? b.id.compareTo(a.id) : jobNumberSort;
  }
  static _compareProjectsForRemove(Project a, Project b) {
    var jobNumberSort = b._jobNumberInPresortedList - a._jobNumberInPresortedList;
    return (jobNumberSort == 0) ? b.id.compareTo(a.id) : jobNumberSort;
  }

  void initFromJSON(Map values) {
    _json = values;

    _oldName = name = values['name'];
    jobNumber = values['jobNumber'];
    initials = values['initials'];
    streetAddress = values['streetAddress'];
    serviceAccountName = values['account'];
    assert(values['_id'] == null || values['_id'] == id);
    rev = values['_rev'];
    _isChanged = false;
  }

  void resetToSavedState() {
    initFromJSON(_json);
  }

  Map jsonGetter() {
    var map = {
      'name': name,
      'jobNumber': (jobNumber is double && jobNumber.isNaN) ? null : jobNumber,
      'initials': initials,
      'streetAddress': streetAddress,
      'account': serviceAccountName,
      'type': 'project'
    };
    if (committed) {
      map['_id'] = id;
      map['_rev'] = rev;
    }
    return map;
  }

  @override notifyChange(ChangeRecord record) {
    if (committed && record is PropertyChangeRecord) {
      _locallyChangedSymbols.add(record.name);
      if ((record.name != #jobNumber && record.name != #serviceAccountName) ||
          record.oldValue != null) {
        isChanged = true;
      }
    }
    super.notifyChange(record);
  }

  static void addAtTail(ObservableList<Project> projects, Project project) {
    project._jobNumberInPresortedList = project.jobNumber;
    projects.add(project);
  }
}
