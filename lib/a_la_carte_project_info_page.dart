library a_la_carte.client.a_la_carte_project_info_page;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:polymer/polymer.dart';
import 'package:paper_elements/paper_autogrow_textarea.dart';
import 'package:paper_elements/paper_input_decorator.dart';
import 'package:paper_elements/paper_action_dialog.dart';
import 'package:intl/intl.dart';
import 'fetch_interop.dart';

import 'package:a_la_carte/models.dart';
import 'package:a_la_carte/json_streaming.dart';
import 'package:a_la_carte/a_la_carte_page_common.dart';
import 'package:a_la_carte/google_map.dart';

@CustomTag('a-la-carte-project-info-page')
class ALaCarteProjectInfoPage extends ALaCartePageCommon {
  @published Project project;
  StreamSubscription _projectSubscription;
  @published int selected = 0;
  @published AppPager appPager;
  @published Presenter appPresenter;
  @published Map<String, Project> projectsByUuid;
  @published List<Project> projects;
  @published String userEmail;
  @published String userName;
  @published Map config;
  @observable bool projectIsCommitted;
  @observable bool showProgress = false;

  final DateFormat formatter = new DateFormat.MMMEd().add_jm();

  StreamSubscription _projectChangeListener;
  bool _fabWillBeDisabled = false;
  final Set<String> _cancelledAuthorizationSubscriptions = new Set<String>();
  StreamSubscription _activeAuthorizationSubscriptionDiscardListener = null;

  ALaCarteProjectInfoPage.created() : super.created() {
    fabIcon = null;
  }

  @override ready() {
    new CompoundObserver()
      ..addPath(this, 'project.jobNumber')
      ..addPath(this, 'project.name')
      ..addPath(this, 'project.serviceAccountName')
      ..open((_) {});
    final PaperAutogrowTextarea streetAddressTextarea =
        $['street-address-textarea'];
    final TextAreaElement textAreaElement =
        streetAddressTextarea.querySelector('textarea');
    textAreaElement.onBlur.listen((event) {
      final address = textAreaElement.value;
      final GoogleMap locationMap = $['location-map'];
      if (!locationMap.addressIsSet && address != null && address != '') {
        locationMap.setAddress(address);
      }
    });
  }

  formatTimeStamp(DateTime time) {
    if (time == null) return '';
    return formatter.format(time);
  }

  void projectChanged(Project oldProject) {
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
      projectIsCommitted = true;
      if (_projectSubscription != null) {
        _projectSubscription.cancel();
      }
    } else {
      projectIsCommitted = false;
      fabIcon = 'check';
    }
    if ((oldProject == null || oldProject.placeId == null) &&
        project.placeId == null) {
      final GoogleMap locationMap = $['location-map'];
      locationMap.resetToInitialState();
    }
    project.placeIdMustBeUpdated = false;
    _projectChangeListener = project.changes.listen(projectFieldsChanged);
  }

  void projectFieldsChanged(List<ChangeRecord> changes) {
    if (project.isChanged) {
      appPager.setProjectHasChanged();
      fabIcon = 'check';
    }
    for (PropertyChangeRecord change in changes) {
      if (change.name == #streetAddress) {
        final PaperAutogrowTextarea streetAddressTextarea =
            $['street-address-textarea'];
        streetAddressTextarea.rows = null;
      } else if (change.name == #jobNumber &&
          (change.newValue == null ||
              (change.newValue is double && change.newValue.isNaN))) {
        final PaperInputDecorator jobNumber = $['jobNumber'];
        jobNumber.isInvalid = true;
      } else if (change.name == #jobNumber &&
          (change.newValue != null &&
              (!(change.newValue is double) || !change.newValue.isNaN))) {
        final PaperInputDecorator jobNumber = $['jobNumber'];
        jobNumber.isInvalid = false;
      } else if (change.name == #name &&
          (change.newValue == null || change.newValue == '')) {
        final PaperInputDecorator name = $['name'];
        name.isInvalid = true;
      } else if (change.name == #name &&
          (change.newValue != null && change.newValue != '')) {
        final PaperInputDecorator name = $['name'];
        name.isInvalid = false;
      }
    }
  }

  @override
  String get backgroundImage => null;

  @override
  void fabAction() {
    _fabWillBeDisabled = true;
    fabDisabled = true;
    //$['showProgress'].classes.add('showing');
    showProgress = true;
    Future _asyncFabAction() async {
      final GoogleMap locationMap = $['location-map'];
      if (locationMap.pinHasMovedFromPlace) {
        var placeId = await locationMap.setPlaceIdFromLatitudeAndLongitude();
        project.placeId = placeId;
      }
      _putProjectDataToServer(project.id, project.json);
    }
    _asyncFabAction();
  }

  void deleteProject(MouseEvent event) {
    PaperActionDialog deleteDialog = $['deleteDialog'];
    deleteDialog.open();
  }

  void confirmDelete(MouseEvent event) {
    if (!project.committed) return;
    _fabWillBeDisabled = true;
    fabDisabled = true;
    //$['showProgress'].classes.add('showing');
    showProgress = true;
    _deleteProjectDataFromServer(project.id, project.rev);
  }

  void _deleteProjectDataFromServer(String id, String rev) {
    var jsonHandler = new JsonStreamingParser();
    final subscription = new Ref<StreamSubscription>();
    subscription.value = jsonHandler.onSymbolComplete.listen((event) =>
        _routeProjectDeletingJsonReply(event, project, subscription, rev, id));

    if (fetch == null) {
      final _request = new HttpRequest();
      _request.open('DELETE', '/a_la_carte/${id}?rev=${rev}');
      _request.setRequestHeader('Content-Type', 'application/json');

      _request.onLoad.listen(jsonHandler.httpRequestListener);
      _request.onProgress.listen(jsonHandler.httpRequestListener);
      _request.onError
          .listen((event) => _onHttpRequestDeletingError(event, _request));

      _request.send();
    } else {
      fetch('/a_la_carte/${id}?rev=${rev}',
          method: 'DELETE',
          headers: {'Content-Type': 'application/json'},
          mode: RequestMode.sameOrigin,
          credentials: RequestCredentials.sameOrigin).then((Response object) {
        jsonHandler.setStreamStateFromResponse(object);
        jsonHandler.streamFromByteStreamReader(object.body.getReader());
      }).catchError((FetchError err) {
        _routeProjectServerError(err.message);
      });
    }
  }

  void _routeProjectDeletingJsonReply(JsonStreamingEvent event, Project project,
      Ref<StreamSubscription> subscription, String rev, String id) {
    final Duration enableDelay = new Duration(milliseconds: 1020);
    if (event.status == 401 && event.path.length == 0) {
      if (event.symbol.containsKey('auth_uri') &&
          event.symbol.containsKey('auth_watcher_id')) {
        appPresenter.showAuthLogin(event.symbol['auth_uri']);
        final activeAuthorizationSubscription = event.symbol["auth_watcher_id"];
        _activeAuthorizationSubscriptionDiscardListener =
            appPager.onDiscardEdits.listen((_) {
          _cancelledAuthorizationSubscriptions
              .add(activeAuthorizationSubscription);
          _cancelSaving();
          _activeAuthorizationSubscriptionDiscardListener.cancel();
        });
        appPresenter.connectTo(
            '/a_la_carte/_changes?feed=continuous&'
            'filter=_doc_ids&doc_ids=%5B%22${activeAuthorizationSubscription}%22%5D',
            (newEvent, subscription) => _routeProjectAuthorizationReply(
                newEvent,
                event,
                subscription,
                activeAuthorizationSubscription,
                () => _deleteProjectDataFromServer(id, rev)),
            isImplicitArray: true);
      } else {
        if (event.symbol.containsKey('auth_uri')) {
          appPresenter.showAuthLogin(event.symbol['auth_uri']);
        }
        _cancelSavingWithErrorFromEvent(event);
        subscription.value.cancel();
      }
    } else if (event.status >= 400 &&
        event.status < 599 &&
        event.path.length == 0) {
      _fabWillBeDisabled = false;
      //$['showProgress'].classes.remove('showing');
      showProgress = false;
      new Timer(enableDelay, () {
        fabDisabled = _fabWillBeDisabled;
      });
      final error = event.symbol['error'];
      String message = event.symbol['reason'];
      switch (error) {
        case 'conflict':
          message = "I couldn't delete the project because someone else"
              " changed it at the same time.";
          break;
      }
      appPresenter.reportError(ErrorReportModule.projectSaver, message);
      subscription.value.cancel();
    } else if (event.status == 200 && event.path.length == 0) {
      _fabWillBeDisabled = false;
      //$['showProgress'].classes.remove('showing');
      showProgress = false;
      new Timer(enableDelay, () {
        fabDisabled = _fabWillBeDisabled;
      });
      if (projectsByUuid.containsKey(project.id)) {
        projectsByUuid.remove(project.id);
        Project.removeFromPresortedList(projects, project);
      }
      appPager.selected = 0;
      subscription.value.cancel();
      appPresenter.receiveAuthenticationSessionData();
      appPresenter.goToDefault();
    }
  }

  void _putProjectDataToServer(String id, Map data) {
    final String body = JSON.encode(project.jsonGetter());
    var jsonHandler = new JsonStreamingParser();
    final subscription = new Ref<StreamSubscription>();
    subscription.value = jsonHandler.onSymbolComplete.listen((event) =>
        _routeProjectSavingJsonReply(event, project, subscription, id, data));

    if (fetch == null) {
      final _request = new HttpRequest();
      _request.open('PUT', '/a_la_carte/${id}');
      _request.setRequestHeader('Content-Type', 'application/json');

      _request.onLoad.listen(jsonHandler.httpRequestListener);
      _request.onProgress.listen(jsonHandler.httpRequestListener);
      _request.onError
          .listen((event) => _onHttpRequestSavingError(event, _request));

      _request.send(body);
    } else {
      fetch('/a_la_carte/${id}',
          method: 'PUT',
          headers: {'Content-Type': 'application/json'},
          mode: RequestMode.sameOrigin,
          credentials: RequestCredentials.sameOrigin,
          body: body).then((Response object) {
        jsonHandler.setStreamStateFromResponse(object);
        jsonHandler.streamFromByteStreamReader(object.body.getReader());
      }).catchError((FetchError err) {
        _routeProjectServerError(err.message);
      });
    }
  }

  void _onHttpRequestSavingError(ProgressEvent event, HttpRequest request) {
    _routeProjectServerError(request.statusText);
  }

  void _onHttpRequestDeletingError(ProgressEvent event, HttpRequest request) {
    _routeProjectServerError(request.statusText);
  }

  void _routeProjectServerError(String err) {
    final Duration enableDelay = new Duration(milliseconds: 1020);
    appPresenter.reportError(ErrorReportModule.projectSaver, err.toString());
    _fabWillBeDisabled = false;
    //$['showProgress'].classes.remove('showing');
    showProgress = false;
    new Timer(enableDelay, () {
      fabDisabled = _fabWillBeDisabled;
    });
    String message = "I couldn't save the changes because the connection to the"
        " server was lost.";
    appPresenter.reportError(ErrorReportModule.projectSaver, message);
  }

  void _cancelSavingWithErrorFromEvent(JsonStreamingEvent event) =>
      _cancelSavingWithError(event.symbol['reason'], event.symbol['message'],
          event.symbol['error']);

  void _cancelSaving() {
    final Duration enableDelay = new Duration(milliseconds: 1020);
    _fabWillBeDisabled = false;
    //$['showProgress'].classes.remove('showing');
    showProgress = false;
    new Timer(enableDelay, () {
      fabDisabled = _fabWillBeDisabled;
    });
  }

  void _cancelSavingWithError(String reason, String message, String error) {
    _cancelSaving();
    if (message == null) {
      message = reason;
      switch (error) {
        case 'conflict':
          message = "I couldn't save the changes because someone else"
              " changed it at the same time.";
          break;
      }
    }
    appPresenter.reportError(ErrorReportModule.projectSaver, message);
  }

  void _routeProjectAuthorizationReply(
      JsonStreamingEvent event,
      JsonStreamingEvent originalEvent,
      Ref<StreamSubscription> subscription,
      String authorizationSubscriptionDocId,
      void _functionToDoAgain()) {
    window.console.log(event.symbol);
    if (event.status >= 300) {
      subscription.value.cancel();
      _cancelSavingWithErrorFromEvent(originalEvent);
      return;
    }
    if (event.path.length == 1 && event.symbol.containsKey('seq')) {
      if (event.symbol.containsKey('deleted') &&
          !_cancelledAuthorizationSubscriptions
              .contains(authorizationSubscriptionDocId)) {
        _functionToDoAgain();
        _activeAuthorizationSubscriptionDiscardListener.cancel();
      }
    } else if (event.path.length == 1 && event.symbol.containsKey('last_seq')) {
      subscription.value.cancel();
      _cancelSavingWithErrorFromEvent(originalEvent);
      return;
    }
  }

  void _routeProjectSavingJsonReply(JsonStreamingEvent event, Project project,
      Ref<StreamSubscription> subscription, String id, Map data) {
    if (event.status == 401 && event.path.length == 0) {
      if (event.symbol.containsKey('auth_uri') &&
          event.symbol.containsKey('auth_watcher_id')) {
        appPresenter.showAuthLogin(event.symbol['auth_uri']);
        final activeAuthorizationSubscription = event.symbol["auth_watcher_id"];
        _activeAuthorizationSubscriptionDiscardListener =
            appPager.onDiscardEdits.listen((_) {
          _cancelledAuthorizationSubscriptions
              .add(activeAuthorizationSubscription);
          _cancelSaving();
          _activeAuthorizationSubscriptionDiscardListener.cancel();
        });
        appPresenter.connectTo(
            '/a_la_carte/_changes?feed=continuous&'
            'filter=_doc_ids&doc_ids=%5B%22${activeAuthorizationSubscription}%22%5D',
            (newEvent, subscription) => _routeProjectAuthorizationReply(
                newEvent,
                event,
                subscription,
                activeAuthorizationSubscription,
                () => _putProjectDataToServer(id, data)),
            isImplicitArray: true);
      } else {
        if (event.symbol.containsKey('auth_uri')) {
          appPresenter.showAuthLogin(event.symbol['auth_uri']);
        }
        _cancelSavingWithErrorFromEvent(event);
        subscription.value.cancel();
      }
    } else if (event.status >= 400 &&
        event.status < 599 &&
        event.path.length == 0) {
      _cancelSavingWithErrorFromEvent(event);
      subscription.value.cancel();
    } else if (event.status == 201 && event.path.length == 0) {
      final Duration enableDelay = new Duration(milliseconds: 1020);
      _fabWillBeDisabled = false;
      //$['showProgress'].classes.remove('showing');
      showProgress = false;
      new Timer(enableDelay, () {
        fabDisabled = _fabWillBeDisabled;
      });
      if (!project.committed) {
        if (!projectsByUuid.containsKey(project.id)) {
          projectsByUuid[project.id] = project;
          Project.insertIntoPresortedList(project, projects);
        }
      } else if (project.jobNumber != project.jobNumberInPresortedList) {
        Project.repositionInPresortedList(projects, project);
      }
      project.rev = event.symbol['rev'];
      project.committed = true;
      projectIsCommitted = true;
      project.isChanged = false;
      project.userDataName = userName;
      project.userDataEmail = userEmail;
      project.userDataTimestamp = new DateTime.now();
      project.projectSyncWithServer();
      appPager.setProjectHasChanged(false);
      fabIcon = null;
      subscription.value.cancel();
      appPresenter.receiveAuthenticationSessionData();
    }
  }
}
