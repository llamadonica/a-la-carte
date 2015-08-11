import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:js';

import 'package:polymer/polymer.dart';
import 'package:paper_elements/paper_toast.dart';
import 'package:a_la_carte/json_streaming.dart';
import 'package:a_la_carte/fetch_interop.dart';
import 'package:uuid/uuid.dart';

import 'package:a_la_carte/models.dart';
// import 'a_la_carte_main_view.dart';

/**
 * A Polymer click counter element.
 */
@CustomTag('a-la-carte-app')
class ALaCarteApp extends PolymerElement implements AppRouter {
  static const Duration minDuration = const Duration(seconds: 1);
  static const Map<String, String> errorMessages = const <String, String>{
    'not_found':
        "I couldn't load the project list. Contact your database administrator."
  };

  @published String templateUrl;
  @observable String selected = 'main-view';
  @observable String prevSelected = null;
  @observable String connectivityErrorMessage = null;
  @observable String moduleErrorMessage = null;
  int responsiveWidth = 600;
  @observable bool wide;
  @observable Project project;
  @observable bool projectsAreLoaded = false;
  @observable bool noProjectsFound = false;
  @observable bool isError = false;
  @observable ObservableList<Project> projects = new ObservableList();
  @observable ObservableMap<String, Project> projectsByUuid =
      new ObservableMap();

  AppRouter get router => this;
  StreamController<List<String>> _onAppNavigationEvent =
      new StreamController<List<String>>();

  HttpRequest _request;
  int _endOfLastRequest = 0;
  int _startOfLastProject = 0;

  AppDelegate __appDelegate;
  DateTime readyTime;
  bool _useFragment = true;

  ALaCarteApp.created() : super.created() {
    _useFragment = !History.supportsState;
  }
  AppDelegate get _appDelegate {
    if (__appDelegate == null) __appDelegate = new AppDelegate();
    return __appDelegate;
  }
  finishStartup() {
    if (window.location.hash == '') {
      setUrl('/+all', '');
      this.selected = 'all';
    } else {
      var regExp = new RegExp(r'^#');
      var url = window.location.hash.replaceFirst(regExp, '/');
      goToUrl(url, setPathFromFragment: true);
    }
    project = new Project(new Uuid().v4());
    window.onPopState.listen(popState);
  }

  handleTemplateError(CustomEvent ev) {}

  void popState(PopStateEvent e) {
    goToUrl(window.location.pathname);
  }
  prepareAnimatedTransition(CustomEvent ev) {
    window.console.log("Preparing transition.");
    new Future(() {
      window.console.log("In transition.");
    });
  }

  @override ready() {
    final PaperToast connectivityToast = $['toast-connectivity'];
    connectivityToast.autoCloseDisabled = true;
    getProjectsData();

    asyncTimer(() {
      finishStartup();
    }, minDuration);
  }

  void goToUrl(String path, {bool setPathFromFragment: false}) {
    _onAppNavigationEvent.add(path.split('/')..removeAt(0));
    if (setPathFromFragment) {
      setUrl(path, '', pushNewState: false);
    }
  }

  void retryProjectsData() {
    final PaperToast connectivityToast = $['toast-connectivity'];
    connectivityToast.dismiss();
    isError = false;
    noProjectsFound = false;
    projectsAreLoaded = false;
    connectivityErrorMessage = null;
    getProjectsData();
  }

  void getProjectsData() {
    final jsonHandler = new JsonStreamingParser();
    connectivityErrorMessage = null;
    jsonHandler.onSymbolComplete.listen(routeProjectLoadingEvent);

    if (fetch == null) {
      _request = new HttpRequest();
      _request.open('GET',
      '/a_la_carte/_design/projects/_view/all_by_job_number?descending=true&include_docs=true');
      _request.setRequestHeader('Accept', 'application/json');

      _request.onLoad.listen(jsonHandler.httpRequestListener);
      _request.onProgress.listen(jsonHandler.httpRequestListener);

      _request.send();
    } else {
      fetch(
          '/a_la_carte/_design/projects/_view/all_by_job_number?descending=true&include_docs=true',
          headers: {'Accept': 'application/json'}).then((object) {
        jsonHandler.setStreamStateFromResponse(object);
        jsonHandler.streamFromByteStreamReader(object.body.getReader());
      });
    }
  }

  _onProjectsDataError(ProgressEvent event) {
    if (_request.status != 200) {
      final json = JSON.decode(_request.responseText);
      connectivityErrorMessage = json['message'];
      if (connectivityErrorMessage == null) {
        connectivityErrorMessage = errorMessages[json['error']];
      }
      final PaperToast connectivityToast = $['toast-connectivity'];
      connectivityToast.show();
    }
  }

  void selectedChanged(String oldSelected) {
    if (oldSelected != selected) prevSelected = oldSelected;
  }

  setUrl(String url, String title, {bool pushNewState: true}) {
    if (_useFragment) {
      final regExp = new RegExp(r'^/');
      url = url.replaceFirst(regExp, '#');
      window.location.assign(url);
      (window.document as HtmlDocument).title = title;
    } else if (pushNewState) {
      window.history.pushState(null, title, url);
    } else {
      window.history.replaceState(null, title, url);
    }
  }

  Stream<List<String>> get onAppNavigationEvent => _onAppNavigationEvent.stream;

  void routeProjectLoadingEvent(JsonStreamingEvent event) {
    if (event.path.length == 1 && event.path[0] == 'error') {
      isError = true;
      if (connectivityErrorMessage == null) {
        connectivityErrorMessage = errorMessages[event.symbol];
      } else {
        final PaperToast connectivityToast = $['toast-connectivity'];
        connectivityToast.show();
        projectsAreLoaded = true;
        noProjectsFound = true;
      }
      return;
    } else if (event.path.length == 1 && event.path[0] == 'message') {
      connectivityErrorMessage = event.symbol;
      return;
    } else if (event.path.length == 0) {
      if (isError && !projectsAreLoaded) {
        final PaperToast connectivityToast = $['toast-connectivity'];
        connectivityToast.show();
        projectsAreLoaded = true;
        noProjectsFound = true;
      }
      return;
    } else if (event.path[0] != 'rows') return;
    if (event.path.length > 2) return;
    if (event.path.length == 2) {
      final project = new Project(event.symbol['id']);
      project.initFromJSON(event.symbol['doc']);
      projects.add(project);
      projectsByUuid[project.id] = project;
      project.committed = true;
      return;
    }
    projectsAreLoaded = true;
    if (projects.length == 0) {
      noProjectsFound = true;
    }
  }

  @override
  void reportError(ErrorReportModule module, String message) {
    moduleErrorMessage = message;
    final PaperToast toastModuleError = $['toast-module-error'];
    toastModuleError.show();
  }

  @override
  Future<int> nextJobNumber(int year) {
    final Completer<int> completer = new Completer<int>();
    final jsonHandler = new JsonStreamingParser();
    jsonHandler.onSymbolComplete.listen((event) => _processNextJobNumber(event, completer, year));
    if (fetch == null) {
      _request = new HttpRequest();
      _request.open('GET',
      '/a_la_carte/_design/projects/_view/greatest_job_number?key=$year');
      _request.setRequestHeader('Accept', 'application/json');

      _request.onLoad.listen(jsonHandler.httpRequestListener);
      _request.onProgress.listen(jsonHandler.httpRequestListener);

      _request.send();
    } else {
      fetch(
          '/a_la_carte/_design/projects/_view/greatest_job_number?key=$year',
          headers: {'Accept': 'application/json'}).then((object) {
        jsonHandler.setStreamStateFromResponse(object);
        jsonHandler.streamFromByteStreamReader(object.body.getReader());
      });
    }
    return completer.future;
  }

  void _processNextJobNumber(JsonStreamingEvent event, Completer<int> completer, int year) {
    if (event.path.length != 0) {
      return;
    }
    if (event.symbol['rows'].length == 0) {
      completer.complete(year*1000 + 1);
    } else {
      completer.complete(event.symbol['rows'][0]['value'] + 1);
    }
  }
}
