import 'dart:html';

import 'package:core_elements/core_animated_pages.dart';
import 'package:paper_elements/paper_button.dart';
import 'package:polymer/polymer.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'a_la_carte_page_common.dart';

/**
 * A Polymer click counter element.
 */
@CustomTag('a-la-carte-card-view')
class ALaCarteCardView extends ALaCartePageCommon {
  @published bool wide;
  @published ObservableList<Project> projects;
  @published Project project;
  @published bool projectsAreLoaded;
  @published bool noProjectsFound;
  @observable bool showSpinner = true;

  @published String appSelected;
  @published String prevAppSelected;
  @published AppPager appPager;

  ALaCarteCardView.created() : super.created();

  @override void domReady() {
    $['loading-cell'].onTransitionEnd.listen((transition) {
      if (projectsAreLoaded) {
        transition.target.classes.add('hidden');
      }
      else {
        transition.target.classes.remove('hidden');
        showSpinner = true;
      }
    });
    $['no-projects-cell'].onTransitionEnd.listen((transition) {
      if (noProjectsFound) {
        transition.target.classes.remove('hidden');
      }
      else {
        transition.target.classes.add('hidden');
      }
    });
  }

  void handleSelect(Event ev) {
    var openCode = (ev.target as PaperButton).getAttribute('data-project-id');
    if (openCode != null) {
      appPager.openProject(openCode);
      (parentNode as CoreAnimatedPages).selected = 'categories';
    }
  }
  void projectsAreLoadedChanged(bool oldValue) {
    if (projectsAreLoaded) {
      showSpinner = false;
      $['loading-cell'].classes.add('hide');
    } else {
      $['loading-cell'].classes.remove('hide');  
    }
  }

  void noProjectsFoundChanged(bool oldValue) {
    if (noProjectsFound) {
      $['no-projects-cell'].classes.remove('hide');
    } else {
      $['no-projects-cell'].classes.add('hide');
    }
  }

  @override
  String get backgroundImage => null;

  @override
  void fabAction() {
    appPager.selected = 1;
  }

  @override
  String get fabIcon => 'add';
}
