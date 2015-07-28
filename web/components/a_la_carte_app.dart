import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:js';

import 'package:polymer/polymer.dart';
import 'package:paper_elements/paper_toast.dart';
import 'package:a_la_carte/json_streaming.dart';
import 'package:a_la_carte/fetch_interop.dart';

import '../models.dart';

/**
 * A Polymer click counter element.
 */
@CustomTag('a-la-carte-app')
class ALaCarteApp extends PolymerElement {
  static const Duration minDuration = const Duration(seconds: 1);
  static const Map<String, String> errorMessages = const <String, String>{
    'not_found':
        "I couldn't load the project list. Contact your database administrator."
  };

  @published String templateUrl;
  @observable String selected = 'categories';
  @observable String prevSelected = null;
  @observable String connectivityErrorMessage = null;
  int RESPONSIVE_WIDTH = 600;
  @observable bool wide;
  @observable Project project;
  @observable bool projectsAreLoaded = false;
  @observable bool noProjectsFound = false;
  @observable bool isError = false;
  @observable ObservableList<Project> projects = new ObservableList() ;

  HttpRequest _request;
  int _endOfLastRequest = 0;
  int _startOfLastProject = 0;

  AppDelegate __appDelegate;
  DateTime readyTime;

  ALaCarteApp.created() : super.created();
  AppDelegate get _appDelegate {
    if (__appDelegate == null) __appDelegate = new AppDelegate();
    return __appDelegate;
  }
  finishStartup() {
    this.selected = 'new-project';
  }

  handleTemplateError(CustomEvent ev) {}

  void popState(PopStateEvent e) {
    if (window.history.state == null) window.history.pushState(
        {'app': 'dgs'}, '');
  }
  prepareAnimatedTransition(CustomEvent ev) {
    window.console.log("Preparing transition.");
    new Future(() {
      window.console.log("In transition.");
    });
  }

  @override ready() {
    PaperToast connectivityToast = $['toast-connectivity'];
    connectivityToast.autoCloseDisabled = true;
    getProjectsData();

    asyncTimer(() {
      finishStartup();
    }, minDuration);
  }

  void regetProjectsData() {
    PaperToast connectivityToast = $['toast-connectivity'];
    connectivityToast.dismiss();
    getProjectsData();
  }

  void getProjectsData() {
    var jsonHandler = new JsonStreamingParser();
    connectivityErrorMessage = null;
    jsonHandler.onSymbolComplete
        .listen(routeProjectLoadingEvent);

    if (fetch == null) {
      _request = new HttpRequest();
      _request.open('GET',
          '/a_la_carte/_design/projects/_view/all_by_job_number?descending=true');
      _request.setRequestHeader('Accept', 'application/json');

      _request.onLoad.listen(jsonHandler.httpRequestListener);
      _request.onProgress.listen(jsonHandler.httpRequestListener);

      _request.send();
    } else {
      fetch('/a_la_carte/_design/projects/_view/all_by_job_number?descending=true',
          headers: {'Accept': 'application/json'})
      .then((object) {
        jsonHandler.setStreamStateFromResponse(object);
        jsonHandler.streamFromByteStreamReader(object.body.getReader());
      });
    }
  }

  _onProjectsDataError(ProgressEvent event) {
    if (_request.status != 200) {
      var json = JSON.decode(_request.responseText);
      connectivityErrorMessage = json['message'];
      if (connectivityErrorMessage == null) {
        connectivityErrorMessage = errorMessages[json['error']];
      }
      PaperToast connectivityToast = $['toast-connectivity'];
      connectivityToast.show();
    }
  }

  void selectedChanged(String oldSelected) {
    if (oldSelected != selected) prevSelected = oldSelected;
  }

  void routeProjectLoadingEvent(JsonStreamingEvent event) {
    if (event.path.length == 1 && event.path[0] == 'error') {
      isError = true;
      if (connectivityErrorMessage == null) {
        connectivityErrorMessage = errorMessages[event.symbol];
      } else {
        PaperToast connectivityToast = $['toast-connectivity'];
        connectivityToast.show();
        projectsAreLoaded = true;
        noProjectsFound = true;
      }
      return;
    }
    else if (event.path.length == 1 && event.path[0] == 'message') {
      connectivityErrorMessage = event.symbol;
      return;
    }
    else if (event.path.length == 0) {
      if (isError && !projectsAreLoaded) {
        PaperToast connectivityToast = $['toast-connectivity'];
        connectivityToast.show();
        projectsAreLoaded = true;
        noProjectsFound = true;
      }
      return;
    }
    else if (event.path[0] != 'rows') return;
    if (event.path.length > 2) return;
    if (event.path.length == 2) {
      final project = new Project(event.symbol['id']);
      project.initFromJSON(event.symbol['value']);
      projects.add(project);
      return;
    }
    projectsAreLoaded = true;
    if (projects.length == 0) {
      noProjectsFound = true;
    }
  }
}
