import 'dart:async';
import 'dart:html';

import 'package:polymer/polymer.dart';
import 'package:paper_elements/paper_toast.dart';
import 'package:a_la_carte/json_streaming.dart';
import 'package:a_la_carte/fetch_interop.dart';
import 'package:uuid/uuid.dart';

import 'package:a_la_carte/models.dart';
import 'a_la_carte_card_view.dart';

/**
 * A Polymer click counter element.
 */

@CustomTag('a-la-carte-presenter')
class ALaCartePresenter extends PolymerElement implements Presenter {
  static const Duration minDuration = const Duration(seconds: 1);
  static const Map<String, String> errorMessages = const <String, String>{
    'not_found':
        "I couldn't load the project list. Contact your database administrator."
  };

  @published String templateUrl;
  @observable String selected = 'main-view';
  @observable String prevSelected = null;
  @observable String connectivityErrorMessage = null;
  int responsiveWidth = 600;
  @observable bool wide;
  @observable Project project;
  @observable bool projectsAreLoaded = false;

  @observable String userEmail = null;
  @observable String userFullName = null;
  @observable String userPicture = null;
  @observable bool isLoggedIn = false;

  Map<String, List<Completer<Project>>> _pendingProjectRequest = new Map();

  Completer _receivingAuthenticationSessionData;

  @ComputedProperty("projectsAreLoaded && projects.length == 0")
  bool get noProjectsFound => readValue(#noProjectsFound);
  @observable bool isError = false;
  @observable ObservableList<Project> projects = new ObservableList();
  @observable ObservableMap<String, Project> projectsByUuid =
      new ObservableMap();

  Presenter get router => this;
  StreamController<List<String>> _onAppNavigationEvent =
      new StreamController<List<String>>();
  HttpRequest _request;
  DateTime readyTime;
  bool _useFragment = true;
  int _currentChangeSeq = 0;
  String _serviceAccountName = null;
  Future _serviceAccountFuture;

  ALaCartePresenter.created() : super.created() {
    _useFragment = !History.supportsState;
  }

  void _finishStartup() {
    if (window.location.hash == '') {
      setUrl('/+all', '');
      this.selected = 'all';
    } else {
      var regExp = new RegExp(r'^#');
      var url = window.location.hash.replaceFirst(regExp, '/');
      _goToUrl(url, setPathFromFragment: true);
    }
    final Completer receivingAuthenticationSessionDataCompleter =
        new Completer();
    connectTo(
        '/_auth/session',
        (event, subscription) => _routeAuthSessionEvent(
            event, subscription, receivingAuthenticationSessionDataCompleter));
    _receivingAuthenticationSessionData =
        receivingAuthenticationSessionDataCompleter;
    window.onPopState.listen(_popState);
  }

  void _popState(PopStateEvent e) {
    _goToUrl(window.location.pathname);
  }

  @override ready() {
    final PaperToast connectivityToast = $['toast-connectivity'];
    connectivityToast.autoCloseDisabled = true;
    _getProjectsData();

    asyncTimer(() {
      _finishStartup();
    }, minDuration);
  }

  void _goToUrl(String path, {bool setPathFromFragment: false}) {
    _onAppNavigationEvent.add(path.split('/')..removeAt(0));
    if (setPathFromFragment) {
      setUrl(path, '', pushNewState: false);
    }
  }

  void retryProjectsData() {
    final PaperToast connectivityToast = $['toast-connectivity'];
    connectivityToast.dismiss();
    isError = false;
    projectsAreLoaded = false;
    connectivityErrorMessage = null;
    _getProjectsData();
  }

  void _getProjectsData() => connectTo(
      '/a_la_carte/_design/projects/_view/all_by_job_number?descending=true&include_docs=true&update_seq=true',
      _routeProjectLoadingEvent);

  @override Future<String> getServiceAccountName() {
    if (_serviceAccountName == null && _serviceAccountFuture == null) {
      _serviceAccountFuture = _getSessionUserName();
    }
    if (_serviceAccountName == null) {
      return _serviceAccountFuture.then((_) => _serviceAccountName);
    }
    return new Future.value(_serviceAccountName);
  }

  Future _getSessionUserName() {
    final completer = new Completer();
    connectTo(
        '/_session',
        (event, subscription) =>
            _routeSessionEvent(event, subscription, completer));
    return completer.future;
  }

  void _routeSessionEvent(JsonStreamingEvent event,
      Ref<StreamSubscription> subscription, Completer completer) {
    if (event.status == 200 && event.path.length == 0) {
      _serviceAccountName = event.symbol['userCtx']['name'];
      subscription.value.cancel();
      completer.complete();
    } else if (event.path.length == 0) {
      _serviceAccountName = '';
      subscription.value.cancel();
      completer.complete();
    }
  }

  _createNewProject(String id, Map doc, [bool isFromPresortedList = true]) {
    final project = new Project(id);
    project.initFromJSON(doc);
    if (project.serviceAccountName == null) {
      getServiceAccountName().then((account) {
        project.serviceAccountName = account;
      });
    }
    if (isFromPresortedList) {
      Project.addAtTail(projects, project);
    } else {
      if (!projectsByUuid.containsKey(project.id)) {
        Project.insertIntoPresortedList(project, projects);
      }
    }
    projectsByUuid[project.id] = project;
    if (_pendingProjectRequest.containsKey(project.id)) {
      for (var completer in _pendingProjectRequest[project.id]) {
        completer.complete(project);
      }
      _pendingProjectRequest.remove(project.id);
    }
    project.committed = true;
  }

  void _routeProjectLoadingEvent(
      JsonStreamingEvent event, Ref<StreamSubscription> subscription) {
    if (event.path.length == 1 && event.path[0] == 'error') {
      isError = true;
      if (connectivityErrorMessage == null) {
        connectivityErrorMessage = errorMessages[event.symbol];
      } else {
        final PaperToast connectivityToast = $['toast-connectivity'];
        connectivityToast.show();
        projectsAreLoaded = true;
      }
      return;
    } else if (event.path.length == 1 && event.path[0] == 'message') {
      connectivityErrorMessage = event.symbol;
      return;
    } else if (event.path.length == 0) {
      if (event.status >= 400 && !projectsAreLoaded) {
        final PaperToast connectivityToast = $['toast-connectivity'];
        connectivityToast.show();
        projectsAreLoaded = true;
      }
      subscription.value.cancel();
      projectsAreLoaded = true;
      for (var uuid in _pendingProjectRequest.keys) {
        final listOfCompleters = _pendingProjectRequest[uuid];
        for (var completer in listOfCompleters) {
          completer.completeError(
              new ArgumentError('No project named $uuid found.'));
        }
      }
      _connectToChangeStream();
      return;
    } else if (event.path.length == 1 && event.path[0] == 'update_seq') {
      _currentChangeSeq = event.symbol;
    } else if (event.path[0] != 'rows') return;
    if (event.path.length > 2) return;
    if (event.path.length == 2) {
      _createNewProject(event.symbol['id'], event.symbol['doc']);
      return;
    }
  }

  @override Future<int> nextJobNumber(int year) {
    final Completer<int> completer = new Completer<int>();
    connectTo(
        '/a_la_carte/_design/projects/_view/greatest_job_number?key=$year',
        (event, subscription) =>
            _processNextJobNumber(event, completer, year, subscription));
    return completer.future;
  }

  void _processNextJobNumber(JsonStreamingEvent event, Completer<int> completer,
      int year, Ref<StreamSubscription> subscription) {
    if (event.path.length != 0) {
      return;
    }
    if (event.symbol['rows'].length == 0) {
      completer.complete(year * 1000 + 1);
    } else {
      completer.complete(event.symbol['rows'][0]['value'] + 1);
    }
    subscription.value.cancel();
  }

  @override
  Future receiveAuthenticationSessionData() {
    if (_receivingAuthenticationSessionData == null) {
      final Completer receivingAuthenticationSessionDataCompleter =
          new Completer();
      connectTo(
          '/_auth/session',
          (event, subscription) => _routeAuthSessionEvent(event, subscription,
              receivingAuthenticationSessionDataCompleter));
      _receivingAuthenticationSessionData =
          receivingAuthenticationSessionDataCompleter;
    }
    return _receivingAuthenticationSessionData.future;
  }

  @override
  void clearAuthenticationSessionData() {
    if (_receivingAuthenticationSessionData != null &&
        !_receivingAuthenticationSessionData.isCompleted) {
      _receivingAuthenticationSessionData.complete();
    }
    _receivingAuthenticationSessionData = null;
    userEmail = userFullName = userPicture = null;
    isLoggedIn = false;
  }

  void _routeAuthSessionEvent(
      JsonStreamingEvent event,
      Ref<StreamSubscription> subscription,
      Completer receivingAuthenticationSessionDataCompleter) {
    if (event.status == 200 && event.path.length == 0 && !isLoggedIn) {
      if (!receivingAuthenticationSessionDataCompleter.isCompleted) {
        userEmail = event.symbol['email'];
        userFullName = event.symbol['fullName'];
        userPicture = event.symbol['picture'];
        if (userEmail != null) {
          isLoggedIn = true;
          receivingAuthenticationSessionDataCompleter.complete(userEmail);
        } else {
          isLoggedIn = false;
          _receivingAuthenticationSessionData = null;
          if (!receivingAuthenticationSessionDataCompleter.isCompleted) {
            receivingAuthenticationSessionDataCompleter.complete(null);
          }
        }
      }
      subscription.value.cancel();
    } else if (event.path.length == 0) {
      subscription.value.cancel();
      _receivingAuthenticationSessionData = null;
      if (!receivingAuthenticationSessionDataCompleter.isCompleted) {
        _receivingAuthenticationSessionData = null;
        receivingAuthenticationSessionDataCompleter.completeError(event.symbol);
      }
    }
  }

  @override
  void connectTo(String uri, JsonEventRouter router,
      {bool isImplicitArray: false, String method: 'GET'}) {
    final jsonHandler = new JsonStreamingParser(isImplicitArray);
    final subscription = new Ref<StreamSubscription>();
    subscription.value = jsonHandler.onSymbolComplete
        .listen((event) => router(event, subscription));

    if (fetch == null) {
      _request = new HttpRequest();
      _request.open(method, uri);
      _request.setRequestHeader('Accept', 'application/json');
      if (!isLoggedIn) {
        _request.setRequestHeader('X-Can-Read-Push-Session-Data', 'true');
        //_request.setRequestHeader('Cookie', window.document.cookie);
      }
      _request.withCredentials = true;

      _request.onLoad.listen(jsonHandler.httpRequestListener);
      var previouslyGotHeaders = new Ref.withValue(false);
      _request.onProgress.listen((ProgressEvent event) {
        if (previouslyGotHeaders.value && _request.readyState >= 2) {
          if (_request.responseHeaders.containsKey('X-Push-Session-Data') &&
              !isLoggedIn) {
            receiveAuthenticationSessionData();
          }
          previouslyGotHeaders.value = true;
        }
        jsonHandler.httpRequestListener(event);
      });

      _request.send();
    } else {
      final headers = {'Accept': 'application/json'};

      if (!isLoggedIn) {
        headers['X-Can-Read-Push-Session-Data'] = 'true';
      }
      fetch(uri,
          method: method,
          headers: headers,
          mode: RequestMode.sameOrigin,
          credentials: RequestCredentials.sameOrigin).then((Response object) {
        if (object.headers.callMethod('has', ['X-Push-Session-Data']) &&
            !isLoggedIn) {
          receiveAuthenticationSessionData();
        }
        jsonHandler.setStreamStateFromResponse(object);
        jsonHandler.streamFromByteStreamReader(object.body.getReader());
      });
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

  @override void goToDefault() => _goToUrl('/+new');

  Stream<List<String>> get onExternalNavigationEvent =>
      _onAppNavigationEvent.stream;

  @override void reportError(ErrorReportModule module, String message) {
    final PaperToast toastModuleError = new PaperToast();
    HtmlElement moduleErrors = $['module-errors'];
    toastModuleError
      ..duration = 5000
      ..text = message
      ..id = new Uuid().v4()
      ..on['core-overlay-close-completed'].listen((_) {
        toastModuleError.remove();
      });
    moduleErrors.append(toastModuleError);
    toastModuleError.show();
  }

  @override Future<Project> ensureProjectIsLoaded(String uuid) {
    if (projectsByUuid.containsKey(uuid)) {
      return new Future.value(projectsByUuid[uuid]);
    } else if (projectsAreLoaded) {
      return new Future.error(
          new ArgumentError('No project named $uuid found.'));
    } else {
      if (!_pendingProjectRequest.containsKey(uuid)) {
        _pendingProjectRequest[uuid] = [];
      }
      final completer = new Completer<Project>();
      _pendingProjectRequest[uuid].add(completer);
      return completer.future;
    }
  }

  void _windowBecomesVisible(
      CustomEvent event, Ref<StreamSubscription> subscription) {
    if (document.visibilityState != 'hidden') {
      _connectToChangeStream();
      subscription.value.cancel();
    }
  }

  Future _connectToChangeStream() async {
    var account = await getServiceAccountName();
    connectTo(
        '/a_la_carte/_changes?feed=continuous&include_docs=true&'
        'since=${_currentChangeSeq}&'
        'filter=projects/projects&account=$account',
        _routeChangeEvent,
        isImplicitArray: true);
  }

  void _routeChangeEvent(
      JsonStreamingEvent event, Ref<StreamSubscription> subscription) {
    if (event.path.length == 1) {
      if (event.symbol.containsKey('seq') &&
          event.symbol.containsKey('id') &&
          !event.symbol.containsKey('deleted')) {
        if (projectsByUuid.containsKey(event.symbol['id'])) {
          ALaCarteCardView cardView = $['main-view'].$['card-view'];
          cardView.visuallyRippleProject(event.symbol['id']);
          final thisProject = projectsByUuid[event.symbol['id']];
          if (thisProject != null && !thisProject.isChanged) {
            thisProject.initFromJSON(event.symbol['doc']);
            if (thisProject.jobNumber != thisProject.jobNumberInPresortedList) {
              Project.repositionInPresortedList(projects, thisProject);
            }
          }
        } else {
          _createNewProject(event.symbol['id'], event.symbol['doc'], false);
        }
      } else if (event.symbol.containsKey('seq') &&
          event.symbol.containsKey('id') &&
          event.symbol.containsKey('deleted')) {
        final thisProject = projectsByUuid[event.symbol['id']];
        if (thisProject != null && !thisProject.isChanged) {
          projectsByUuid.remove(thisProject.id);
          Project.removeFromPresortedList(projects, thisProject);
        }
      }
      if (event.symbol.containsKey('seq')) {
        _currentChangeSeq = event.symbol['seq'];
      } else if (event.symbol.containsKey('last_seq')) {
        _currentChangeSeq = event.symbol['last_seq'];
        subscription.value.cancel();
        if (document.visibilityState == 'hidden') {
          final subscription = new Ref<StreamSubscription>();
          subscription.value = document.onVisibilityChange
              .listen((event) => _windowBecomesVisible(event, subscription));
        } else {
          //Reconnect
          _connectToChangeStream();
        }
      }
    }
  }

  @override void showAuthLogin(String uri) {
    window.open(uri, '_blank',
        'width=500,height=500,centerscreen=1,toolbar=0,navigation=0');
  }
}
