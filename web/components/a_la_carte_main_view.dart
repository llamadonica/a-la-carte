import 'dart:html';
import 'dart:async';

import 'package:core_elements/core_animated_pages.dart';
import 'package:paper_elements/paper_input.dart';
import 'package:polymer/polymer.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'a_la_carte_page_common.dart';

/**
 * A Polymer click counter element.
 */
@CustomTag('a-la-carte-main-view')
class ALaCarteMainView extends PolymerElement implements AppPager {
  @published bool wide;
  @published Project project;
  @published ObservableList<Project> projects;
  @published bool projectsAreLoaded;
  @published bool noProjectsFound;

  @published String prevAppSelected;
  List<String> appAllSelectable = ['+all', '+new'];
  @published String responsiveWidth;

  @observable String navigation = "Basic Settings";

  @observable ALaCartePageCommon currentPage;
  @observable ObservableList<ALaCartePageCommon> pages;
  @PublishedProperty(reflect: true) int selected = 0;

  @published AppRouter appRouter;
  StreamSubscription<List<String>> _appRouterNavigationSubscription;
  List<String> allSelectable = <String>['+all', '+new'];

  void appRouterChanged(AppRouter oldAppRouter) {
    if (_appRouterNavigationSubscription != null) {
      _appRouterNavigationSubscription.cancel();
    }
    appRouter.onAppNavigationEvent.listen(onAppNavigationEvent);
  }

  ALaCarteMainView.created() : super.created();

  ready() {
    pages = new ObservableList.from(
        shadowRoot.querySelectorAll('core-pages.content > *')
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
    appRouter.setUrl('/${appAllSelectable[selected]}','');
    if (selected >= pages.length) {
      currentPage = null;
    } else {
      currentPage = pages[selected];
    }
  }

  void onAppNavigationEvent(List<String> event) {
    if (event.length < 1) {
      appRouter.setUrl('/+all','');
      return;
    }
    switch (event[0]) {
      case '+all':
        selected = 0;
        break;
      case '+new':
        selected = 1;
        project = new Project(new Uuid().v4());
        break;
    }

  }

  void setToNewProject() {
    project = new Project(new Uuid().v4());
  }
  void openProject(String uuid) {
    //TODO: implement openProject;
  }
}
