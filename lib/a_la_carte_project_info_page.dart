import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:polymer/polymer.dart';
import 'package:paper_elements/paper_autogrow_textarea.dart';
import 'package:paper_elements/paper_input_decorator.dart';
import 'fetch_interop.dart';

import 'package:a_la_carte/models.dart';
import 'package:a_la_carte/json_streaming.dart';
import 'package:a_la_carte/a_la_carte_page_common.dart';

@CustomTag('a-la-carte-project-info-page')
class ALaCarteProjectInfoPage extends ALaCartePageCommon {
  @published Project project;
  StreamSubscription _projectSubscription;
  @published int selected = 0;
  @published AppPager appPager;
  @published Map<String, Project> projectsByUuid;
  @published List<Project> projects;
  StreamSubscription _projectChangeListener;
  bool _fabWillBeDisabled = false;
  @observable bool showProgress;

  ALaCarteProjectInfoPage.created() : super.created() {
    fabIcon = null;
    showProgress = false;
  }

  void projectChanged(oldProject) {
    final PaperAutogrowTextarea streetAddressTextarea =
        $['street-address-textarea'];
    final String streetAddress =
        project.streetAddress == null ? '' : project.streetAddress;
    final streetAddressRows = streetAddress.split('\n').length;
    streetAddressTextarea.rows = streetAddressRows;
    if (_projectChangeListener != null) {
      _projectChangeListener.cancel();
    }
    final PaperInputDecorator name = $['name'];
    if (project.name == null) {
      name.isInvalid = true;
    } else {
      name.isInvalid = false;
    }
    final PaperInputDecorator jobNumber = $['jobNumber'];
    if (project.jobNumber == null) {
      jobNumber.isInvalid = true;
    } else {
      jobNumber.isInvalid = false;
    }
    if (project.committed) {
      fabIcon = null;
      if (_projectSubscription != null) {
        _projectSubscription.cancel();
      }
    } else {
      fabIcon = 'check';
    }
    _projectChangeListener = project.changes.listen(projectFieldsChanged);
  }

  void projectFieldsChanged(List<ChangeRecord> changes) {
    project.isChanged = true;
    appPager.setProjectHasChanged();
    fabIcon = 'check';
    for (PropertyChangeRecord change in changes) {
      if (change.name == #streetAddress) {
        final PaperAutogrowTextarea streetAddressTextarea = $['street-address-textarea'];
        streetAddressTextarea.rows = null;
      } else if (change.name == #jobNumber &&
          (change.newValue == null || (change.newValue is double && change.newValue.isNaN))) {
        final PaperInputDecorator jobNumber = $['jobNumber'];
        jobNumber.isInvalid = true;
      } else if (change.name == #jobNumber &&
          (change.newValue != null && (!(change.newValue is double) || !change.newValue.isNaN))) {
        final PaperInputDecorator jobNumber = $['jobNumber'];
        jobNumber.isInvalid = false;
      } else if (change.name == #name && (change.newValue == null || change.newValue == '')) {
        final PaperInputDecorator name = $['name'];
        name.isInvalid = true;
      } else if (change.name == #name && (change.newValue != null && change.newValue != '')) {
        final PaperInputDecorator name = $['name'];
        name.isInvalid = false;
      }
    }
  }

  // TODO: implement backgroundImage
  @override
  String get backgroundImage => null;

  @override
  void fabAction() {
    _fabWillBeDisabled = true;
    fabDisabled = true;
    showProgress = true;
    putProjectDataToServer(project.id, project.json);
  }

  void putProjectDataToServer(String id, Map data) {
    final String body = JSON.encode(project.jsonGetter());
    var jsonHandler = new JsonStreamingParser();
    jsonHandler.onSymbolComplete.listen((event) => routeProjectSavingJsonReply(event, project));

    if (fetch == null) {
      final _request = new HttpRequest();
      _request.open('PUT', '/a_la_carte/${id}');
      _request.setRequestHeader('Content-Type', 'application/json');

      _request.onLoad.listen(jsonHandler.httpRequestListener);
      _request.onProgress.listen(jsonHandler.httpRequestListener);

      _request.send(body);
    } else {
      fetch('/a_la_carte/${id}',
          method: 'PUT', headers: {'Content-Type': 'application/json'},
      body: body)
      .then((Response object) {
        jsonHandler.setStreamStateFromResponse(object);
        jsonHandler.streamFromByteStreamReader(object.body.getReader());
      });
    }
  }

  void routeProjectSavingJsonReply(JsonStreamingEvent event, Project project) {
    final Duration enableDelay = new Duration(milliseconds: 1020);
    if (event.status >= 400 && event.status < 599 && event.path.length == 0) {
      _fabWillBeDisabled = false;
      showProgress = false;
      new Timer(enableDelay, () {
          fabDisabled = _fabWillBeDisabled;
      });
      final error = event.symbol['error'];
      String message = event.symbol['reason'];
      switch (error) {
        case 'conflict':
          message = "I couldn't save the changes because someone else"
          " changed it at the same time.";
          break;
      }
      appPager.reportError(ErrorReportModule.projectSaver, message);
    } else if (event.status == 201 && event.path.length == 0) {
      _fabWillBeDisabled = false;
      showProgress = false;
      new Timer(enableDelay, () {
          fabDisabled = _fabWillBeDisabled;
      });
      if (!project.committed) {
        projectsByUuid[project.id] = project;
        Project.insertIntoPresortedList(project, projects);
      }
      project.rev = event.symbol['rev'];
      project.committed = true;
      project.isChanged = false;
      appPager.setProjectHasChanged(false);
      fabIcon = null;
    }
  }
}
