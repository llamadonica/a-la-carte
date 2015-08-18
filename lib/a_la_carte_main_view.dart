import 'dart:html';
import 'dart:async';

import 'package:core_elements/core_animated_pages.dart';
import 'package:paper_elements/paper_action_dialog.dart';
import 'package:paper_elements/paper_input.dart';
import 'package:polymer/polymer.dart';
import 'package:uuid/uuid.dart';

import 'package:a_la_carte/models.dart';
import 'package:a_la_carte/a_la_carte_page_common.dart';

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


  @observable String projectEditViewCaption = "Add a project";
  @observable ALaCartePageCommon currentPage;
  @observable ObservableList<ALaCartePageCommon> pages;
  @PublishedProperty(reflect: true) int selected = 0;
  @observable int selectedPage = 0;
  @published Presenter appPresenter;

  List<String> allSelectable = <String>['+all', '+new'];
  List<String> appAllSelectable = ['+all', '+new'];
  Stream get onDiscardEdits => _onDiscardEditsController.stream;

  StreamSubscription<List<String>> _appRouterNavigationSubscription;
  final StreamController _onDiscardEditsController = new StreamController();
  String _projectLookupId;


  void appRouterChanged(Presenter oldAppRouter) {
    if (_appRouterNavigationSubscription != null) {
      _appRouterNavigationSubscription.cancel();
    }
    appPresenter.onExternalNavigationEvent.listen(_onAppNavigationEvent);
  }

  ALaCarteMainView.created() : super.created();

  ready() {
    pages = new ObservableList.from(shadowRoot
        .querySelectorAll('core-pages.content > *')
        .where((e) => e is ALaCartePageCommon));
    if (selected >= pages.length) {
      currentPage = null;
    } else {
      currentPage = pages[selected];
    }
  }

  routeFabAction(CustomEvent ev) {
    if (currentPage == null) return;
    currentPage.fabAction();
  }

  selectedChanged(int oldValue) {
    if (selected == 1 && project != null && project.isChanged && project.committed) {
      appPresenter.setUrl('/+edit/${project.id}', '');
    }
    else if (selected == 1 && project == null) {
      appPresenter.setUrl('/+view/${_projectLookupId}', '');
    }
    else if (selected == 1 && project.committed) {
      appPresenter.setUrl('/+view/${project.id}', '');
    }
    else {
      appPresenter.setUrl('/${appAllSelectable[selected]}', '');
    }
    if (selected >= pages.length) {
      currentPage = null;
    } else {
      currentPage = pages[selected];
    }
    if (project != null && project.isChanged && selected == 0 && selectedPage == 1) {
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

  void _onAppNavigationEvent(List<String> event) {
    if (event.length < 1) {
      appPresenter.setUrl('/+all', '');
      return;
    }
    switch (event[0]) {
      case '+all':
        selected = 0;
        break;
      case '+new':
        selected = 1;
        setToNewProject();
        break;
      case '+edit':
      case '+view':
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
      window.console.log('Found project $uuid');
    }, onError: (err) {
      appPresenter.setUrl('/+new', '');
      _onAppNavigationEvent(['+new']);
      window.console.log('Could not find project $uuid');
    });
  }

  @override void setProjectHasChanged([bool changed=true]) {
    if (selected == 1 && changed && project.committed) {
      appPresenter.setUrl('/+edit/${project.id}', '');
      projectEditViewCaption = "Edit this project";
    } else if (selected == 1 && project.committed) {
      appPresenter.setUrl('/+view/${project.id}', '');
      projectEditViewCaption = "View this project";
    }
  }

  @override void reportError(ErrorReportModule module, String errorMessage) => appPresenter.reportError(module, errorMessage);

  @override Future<int> nextJobNumber(int year) => appPresenter.nextJobNumber(year);

}
