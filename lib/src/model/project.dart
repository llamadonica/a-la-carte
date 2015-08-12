part of a_la_carte_models;

typedef int Comparator<T>(T a, T b);

class Project extends JsonCanSync {
  final String id;

  bool committed = false;
  bool isChanged = false;

  @observable String name;
  String _oldName;
  @observable num jobNumber;
  @observable bool isActive;
  @observable String initials;
  @observable String streetAddress;

  String rev;

  Map _json = {};
  Project(String this.id);
  Map get json => _json;

  static insertIntoPresortedList(Project project, List<Project> projects,
                                 [Comparator comparison = null]) {
    if (comparison == null) {
      comparison = _compareProjects;
    }
    var projectsMax = projects.length;
    var projectsMin = 0;
    var projectsDelta = projectsMax >> 1;
    while (projectsDelta > 0) {
      final compareProject = projects[projectsMin + projectsDelta];
      if (comparison(compareProject, project) > 0) {
        projectsMin += projectsDelta;
      }
      projectsDelta >>= 1;
    }
    projects.insert(projectsMin, project);
  }

  static _compareProjects(Project a, Project b) => (b.jobNumber - a.jobNumber);

  void initFromJSON(Map values) {
    _json = values;

    _oldName = name = values['name'];
    jobNumber = values['jobNumber'];
    initials = values['initials'];
    streetAddress = values['streetAddress'];
    assert(values['_id'] == null || values['_id'] == id);
    rev = values['_rev'];
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
      'type': 'project'
    };
    if (committed) {
      map['_id'] = id;
      map['_rev'] = rev;
    }
    return map;
  }
}
