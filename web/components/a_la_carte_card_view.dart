import 'dart:html';

import 'package:core_elements/core_animated_pages.dart';
import 'package:paper_elements/paper_button.dart';
import 'package:polymer/polymer.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

/**
 * A Polymer click counter element.
 */
@CustomTag('a-la-carte-card-view')
class ALaCarteCardView extends PolymerElement {
  @published bool wide;
  @published ObservableList<Project> projects;
  @published Project project;
  @published bool projectsAreLoaded;
  @published bool noProjectsFound;
  @observable bool showSpinner = true;

  @published String appSelected;
  @published String prevAppSelected;

  ALaCarteCardView.created() : super.created();

  @override void domReady() {
    var subscription = $['loading-cell'].onTransitionEnd.listen((transition) {
      if (projectsAreLoaded) {
        transition.target.classes.add('hidden');
      }
      else {
        transition.target.classes.remove('hidden');
        showSpinner = true;
      }
    });
  }

  void handleSelect(Event ev) {
    var openCode = (ev.target as PaperButton).getAttribute('data-project-id');
    if (openCode != null) {
      project = projects[openCode];
      (parentNode as CoreAnimatedPages).selected = 'categories';
    }
  }
  void projectsAreLoadedChanged(bool oldValue) {
    if (projectsAreLoaded) {
      showSpinner = false;
    }
  }
}
