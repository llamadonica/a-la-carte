import 'dart:async';
import 'dart:html';

import 'package:polymer/polymer.dart';
import 'fetch_interop.dart';

import 'package:a_la_carte/models.dart';
import 'package:a_la_carte/a_la_carte_page_common.dart';

@CustomTag('a-la-carte-project-info-page')
class ALaCarteProjectInfoPage extends ALaCartePageCommon {
  @published Project project;
  StreamSubscription _projectSubscription;
  @published int selected = 0;
  @published AppPager appPager;
  ALaCarteProjectInfoPage.created() : super.created() {
    fabIcon = null;
  }

  void projectChanged(oldProject) {
    if (project.committed) {
      fabIcon = null;
      if (_projectSubscription != null) {
        _projectSubscription.cancel();
      }
      project.changes.listen(projectFieldsChanged);
    } else {
      fabIcon = 'check';
    }
  }

  void projectFieldsChanged(List<ChangeRecord> changes) {
    project.isChanged = false;
    fabIcon = 'check';
  }

  // TODO: implement backgroundImage
  @override
  String get backgroundImage =>
      'https://www.polymer-project.org/components/core-scroll-header-panel/demos/images/bg9.jpg';

  @override
  void fabAction() {
    putProjectData(project.json);
  }

  void putProjectData(Map data) {
    if (fetch == null) {
      final _request = new HttpRequest();
      _request.open('PUT', '/a_la_carte/${data["id"]}');
      _request.setRequestHeader('Accept', 'application/json');

      _request.send();
    } else {
      fetch('/a_la_carte/${data["id"]}',
          method: 'PUT', headers: {'Accept': 'application/json'});
    }
  }
}
