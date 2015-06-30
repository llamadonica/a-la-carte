import 'dart:html';

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
class ALaCarteMainView extends PolymerElement {
  @published bool wide;
  @published Project project;
  @published ObservableList<Project> projects;
  @published bool projectsAreLoaded;
  @published bool noProjectsFound;

  @published String appSelected;
  @published String prevAppSelected;
  @published String responsiveWidth;
  
  @observable String navigation = "Basic Settings";
  @observable int selected = 0;
  
  @observable ALaCartePageCommon currentPage;
  @observable ObservableList<ALaCartePageCommon> pages;
    
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
    if (selected >= pages.length) {
      currentPage = null;
    } else {
      currentPage = pages[selected];
    }
  }
}
