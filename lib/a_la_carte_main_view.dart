library a_la_carte.client.a_la_carte_main_view;

import 'dart:html';
import 'dart:async';

import 'package:core_elements/core_input.dart';
import 'package:paper_elements/paper_action_dialog.dart';
import 'package:polymer/polymer.dart';
import 'package:uuid/uuid.dart';

import 'package:a_la_carte/models.dart';
import 'package:a_la_carte/json_streaming.dart';
import 'package:a_la_carte/fetch_interop.dart';
import 'package:a_la_carte/a_la_carte_page_common.dart';
import 'package:a_la_carte/a_la_carte_scaffold.dart';

/**
 * A Polymer click counter element.
 */
@CustomTag('a-la-carte-main-view')
class ALaCarteMainView extends PolymerElement implements AppPager {
  @published bool wide;
  @published Project project;
  @published ObservableList<Project> projects;
  @published Map<String, Project> projectsByUuid;
  @published bool projectsAreLoaded;
  @published bool noProjectsFound;
  @published String prevAppSelected;
  @published String responsiveWidth;
  @published bool isLoggedIn;
  @published String userPicture;
  @published String userName;
  @published String userEmail;
  @published Map config;
  @observable String internalUserPicture;

  @observable String projectEditViewCaption = "Add a project";
  @observable ALaCartePageCommon currentPage;
  @observable ObservableList<ALaCartePageCommon> pages;
  @observable CoreInput searchInput;
  @observable String searchText;
  @PublishedProperty(reflect: true) int selected = 0;
  @observable int selectedPage = 0;
  @published Presenter appPresenter;

  int _oldSelected = 0;

  List<String> allSelectable = <String>['a', 'n'];
  List<String> appAllSelectable = ['a', 'n', 's'];

  bool _isInSearchMode = false;

  Ref _currentPageClickSubscriber;
  Stream get onDiscardEdits => _onDiscardEditsController.stream;

  StreamSubscription<List<String>> _appRouterNavigationSubscription;
  final StreamController _onDiscardEditsController = new StreamController();
  String _projectLookupId;

  void isLoggedInChanged(bool oldValue) {
    if (oldValue && !isLoggedIn) {
      $['tap-sign-in']
        ..classes.add('showing')
        ..onTransitionEnd.first.then((_) {
          $['tap-sign-in'].classes.remove('showing');
        });

      $['tap-account-page']
        ..classes.add('hiding')
        ..onTransitionEnd.first.then((_) {
          $['tap-account-page'].classes.remove('hiding');
        });
    } else if (!oldValue && isLoggedIn) {
      $['tap-sign-in'].classes.remove('showing');
      $['tap-account-page'].classes.remove('hiding');
    }
  }

  void userPictureChanged(String oldUserPicture) {
    if (userPicture != null) internalUserPicture = userPicture;
  }

  void appRouterChanged(Presenter oldAppRouter) {
    if (_appRouterNavigationSubscription != null) {
      _appRouterNavigationSubscription.cancel();
    }
    _appRouterNavigationSubscription =
        appPresenter.onExternalNavigationEvent.listen(_onAppNavigationEvent);
  }

  void searchTextChanged(String oldSearchText) {
    if (selected != 2) {
      _oldSelected = selected;
      selected = 2;
    }
  }

  ALaCarteMainView.created() : super.created();

  ready() {
    searchInput = $['search-input'];
    pages = new ObservableList.from(shadowRoot
        .querySelectorAll('core-pages.content > *')
        .where((e) => e is ALaCartePageCommon));
    if (selected >= pages.length) {
      currentPage = null;
    } else {
      currentPage = pages[selected];
    }
    _appRouterNavigationSubscription =
        appPresenter.onExternalNavigationEvent.listen(_onAppNavigationEvent);
  }

  routeFabAction(CustomEvent ev) {
    if (currentPage == null) return;
    currentPage.fabAction();
  }

  _clearSearchMode() {
    HtmlElement element = $['search-bar'];
    element
      ..attributes['hiding'] = ''
      ..onTransitionEnd.first.then((_) {
        if (element.attributes.containsKey('hiding')) {
          element..attributes.remove('hiding')..attributes.remove('showing');
        }
      });
    ALaCarteScaffold scaffold = $['scaffold'];
    scaffold.undockHeader();
    $['tap-sign-in'].classes.remove('utility');
    _isInSearchMode = false;
    if (_currentPageClickSubscriber.value != null) {
      _currentPageClickSubscriber.value.cancel();
      _currentPageClickSubscriber.value = null;
    }
  }

  selectedChanged(int oldValue) {
    if (selected == 1 &&
        project != null &&
        project.isChanged &&
        project.committed) {
      appPresenter.setUrl('#/e/${project.id}', '');
    } else if (selected == 1 && project == null) {
      appPresenter.setUrl('#/v/${_projectLookupId}', '');
    } else if (selected == 1 && project.committed) {
      appPresenter.setUrl('#/v/${project.id}', '');
    } else {
      appPresenter.setUrl('#/${appAllSelectable[selected]}', '');
    }
    if (_isInSearchMode && selected != 2) {
      _clearSearchMode();
    }
    if (selected >= pages.length) {
      currentPage = null;
    } else {
      currentPage = pages[selected];
    }
    if (project != null &&
        project.isChanged &&
        selected == 0 &&
        selectedPage == 1) {
      PaperActionDialog discardDialog = $['discardDialog'];
      discardDialog.open();
      return;
    }
    selectedPage = selected;
    if (selected == 0) {
      setToNewProject();
    }
  }

  void confirmDiscardEdits(MouseEvent event) {
    selectedPage = selected;
    project.resetToSavedState();
    setToNewProject();
    _onDiscardEditsController.add(null);
  }

  void cancelDiscardEdits(MouseEvent event) {
    selected = selectedPage;
  }

  void tapSignIn(MouseEvent event) {
    appPresenter.connectTo('/_auth/login', _routeLoginReply);
  }

  void tapSignOut(MouseEvent event) {
    _connectToWithOptionalBody(
        '/_auth/session', _routeLogoutReply, _finalizeLogout,
        method: 'DELETE');
    $['personal-info-dropdown'].close();
  }

  void tapAccountInfo(MouseEvent event) {
    $['personal-info-dropdown'].toggle();
  }

  void openArrow(CustomEvent event) {
    $['arrow-holder'].classes.add('showing');
    $['arrow-holder'].style.opacity = '1';
  }

  void removeArrow(CustomEvent event) {
    $['arrow-holder'].classes.remove('showing');
    $['arrow-holder'].style.opacity = '0';
  }

  void _onAppNavigationEvent(List<String> event) {
    if (event.length < 1) {
      appPresenter.setUrl('#/all', '');
      return;
    }
    switch (event[0]) {
      case 'a':
        selected = 0;
        break;
      case 'n':
        selected = 1;
        setToNewProject();
        break;
      case 'e':
      case 'v':
        selected = 1;
        openProject(_projectLookupId = event[1]);
        break;
    }
  }

  @override void setToNewProject() {
    project = new Project(new Uuid().v4());
    projectEditViewCaption = "Add a project";
    DateTime currentTime = new DateTime.now();
    appPresenter.nextJobNumber(currentTime.year).then((nextNumber) {
      if (project.jobNumber == null) {
        project.jobNumber = nextNumber;
      }
    });
    appPresenter.getServiceAccountName().then((serviceAccount) {
      project.serviceAccountName = serviceAccount;
    });
  }

  @override void openProject(String uuid) {
    appPresenter.ensureProjectIsLoaded(uuid).then((foundProject) {
      project = foundProject;
      projectEditViewCaption = "View this project";
    }, onError: (err) {
      appPresenter.setUrl('#/n', '');
      _onAppNavigationEvent(['n']);
    });
  }

  @override void setProjectHasChanged([bool changed = true]) {
    if (selected == 1 && changed && project.committed) {
      appPresenter.setUrl('#/e/${project.id}', '');
      projectEditViewCaption = "Edit this project";
    } else if (selected == 1 && project.committed) {
      appPresenter.setUrl('#/v/${project.id}', '');
      projectEditViewCaption = "View this project";
    }
  }

  void reportError(ErrorReportModule module, String errorMessage) =>
      appPresenter.reportError(module, errorMessage);

  Future<int> nextJobNumber(int year) => appPresenter.nextJobNumber(year);

  void _connectToWithOptionalBody(
      String uri, JsonEventRouter router, Function callOnCompleteWithNoBody,
      {bool isImplicitArray: false, String method: 'GET'}) {
    final jsonHandler = new JsonStreamingParser(isImplicitArray);
    final subscription = new Ref<StreamSubscription>();
    subscription.value = jsonHandler.onSymbolComplete
        .listen((event) => router(event, subscription));

    if (fetch == null) {
      var _request = new HttpRequest();
      _request.open(method, uri);
      _request.setRequestHeader('Accept', 'application/json');
      _request.withCredentials = true;

      _request.onLoad.listen(jsonHandler.httpRequestListener);
      var previouslyGotHeaders = new Ref.withValue(false);
      _request.onProgress.listen((ProgressEvent event) {
        if (previouslyGotHeaders.value && _request.readyState >= 2) {
          previouslyGotHeaders.value = true;
          if (_request.status == 201) {
            callOnCompleteWithNoBody();
            subscription.value.cancel();
          }
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
        if (object.status == 201) {
          callOnCompleteWithNoBody();
          subscription.value.cancel();
        }
        jsonHandler.setStreamStateFromResponse(object);
        jsonHandler.streamFromByteStreamReader(object.body.getReader());
      });
    }
  }

  void _routeLoginReply(
      JsonStreamingEvent event, Ref<StreamSubscription> subscription) {
    if (event.status == 401 && event.path.length == 0) {
      if (event.symbol.containsKey('auth_uri') &&
          event.symbol.containsKey('auth_watcher_id')) {
        appPresenter.showAuthLogin(event.symbol['auth_uri']);
        final activeAuthorizationSubscription = event.symbol["auth_watcher_id"];
        appPresenter.connectTo(
            '/a_la_carte/_changes?feed=continuous&'
            'filter=_doc_ids&doc_ids=%5B%22${activeAuthorizationSubscription}%22%5D',
            (newEvent, subscription) => _routeProjectAuthorizationReply(
                newEvent, subscription, activeAuthorizationSubscription),
            isImplicitArray: true);
      } else {
        if (event.symbol.containsKey('auth_uri')) {
          appPresenter.showAuthLogin(event.symbol['auth_uri']);
        }
      }
    } else if (event.status == 200 && event.path.length == 0) {
      appPresenter.receiveAuthenticationSessionData();
    } else if (event.path.length == 0) {
      appPresenter.reportError(ErrorReportModule.login, 'Could not log in.');
      subscription.value.cancel();
    }
  }

  void _routeLogoutReply(
      JsonStreamingEvent event, Ref<StreamSubscription> subscription) {
    if (event.status == 401 || event.status == 404 && event.path.length == 0) {
    } else if (event.status == 200 ||
        event.status == 201 && event.path.length == 0) {
      _finalizeLogout();
      subscription.value.cancel();
    } else if (event.path.length == 0) {
      appPresenter.reportError(ErrorReportModule.login, 'Could not log out.');
      subscription.value.cancel();
    }
  }

  void _finalizeLogout() {
    appPresenter.clearAuthenticationSessionData();
  }

  void _routeProjectAuthorizationReply(
      JsonStreamingEvent event,
      Ref<StreamSubscription> subscription,
      String activeAuthorizationSubscription) {
    if (event.status >= 300) {
      subscription.value.cancel();
      return;
    }
    if (event.path.length == 1 && event.symbol.containsKey('seq')) {
      if (event.symbol.containsKey('deleted')) {
        appPresenter.receiveAuthenticationSessionData();
        subscription.value.cancel();
      }
    } else if (event.path.length == 1 && event.symbol.containsKey('last_seq')) {
      subscription.value.cancel();
      return;
    }
  }

  void tapSearchButton(MouseEvent event) {
    _isInSearchMode = true;
    HtmlElement element = $['search-bar'];
    element
      ..attributes['showing'] = ''
      ..attributes.remove('hiding');
    ALaCarteScaffold scaffold = $['scaffold'];
    scaffold.dockHeader();
    $['tap-sign-in'].classes.add('utility');
    if (currentPage != null && currentPage.id != 'search-page') {
      _currentPageClickSubscriber = new Ref();
      _currentPageClickSubscriber.value = currentPage.onMouseDown.listen((_) =>
        _clearSearchMode());
    }
  }

  void tapSearchClear(MouseEvent event) {
    _clearSearchMode();
  }
}
