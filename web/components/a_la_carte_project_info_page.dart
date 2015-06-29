import 'dart:async';
import 'dart:html';

import 'package:polymer/polymer.dart';

import '../models.dart';
import 'a_la_carte_page_common.dart';

@CustomTag('a-la-carte-project-info-page')
class ALaCarteProjectInfoPage extends ALaCartePageCommon {
  @published Project project;
  @published int selected = 0;
  ALaCarteProjectInfoPage.created() : super.created();
  
  // TODO: implement backgroundImage
  @override
  String get backgroundImage => 'https://www.polymer-project.org/components/core-scroll-header-panel/demos/images/bg9.jpg';

  @override
  void fabAction() {
    window.alert('Hello World!');
  }

  @override
  String get fabIcon => 'arrow-back';
}
