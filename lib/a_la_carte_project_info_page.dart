import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:polymer/polymer.dart';
import 'package:paper_elements/paper_autogrow_textarea.dart';
import 'package:paper_elements/paper_input_decorator.dart';
import 'fetch_interop.dart';

import 'package:a_la_carte/models.dart';
import 'package:a_la_carte/a_la_carte_page_common.dart';

@CustomTag('a-la-carte-project-info-page')
class ALaCarteProjectInfoPage extends ALaCartePageCommon {
  @published Project project;
  StreamSubscription _projectSubscription;
  @published int selected = 0;
  @published AppPager appPager;
  StreamSubscription _projectChangeListener;
  ALaCarteProjectInfoPage.created() : super.created() {
    fabIcon = null;
  }

  void projectChanged(oldProject) {
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
      if (_projectSubscription != null) {
        _projectSubscription.cancel();
      }
    } else {
      fabIcon = 'check';
    }
    _projectChangeListener = project.changes.listen(projectFieldsChanged);
  }

  void projectFieldsChanged(List<ChangeRecord> changes) {
    project.isChanged = true;
    appPager.setProjectHasChanged();
    fabIcon = 'check';
    for (PropertyChangeRecord change in changes) {
      if (change.name == #streetAddress) {
        final PaperAutogrowTextarea streetAddressTextarea = $['street-address-textarea'];
        streetAddressTextarea.rows = null;
      } else if (change.name == #jobNumber &&
          (change.newValue == null || (change.newValue is double && change.newValue.isNaN))) {
        final PaperInputDecorator jobNumber = $['jobNumber'];
        jobNumber.isInvalid = true;
      } else if (change.name == #jobNumber &&
          (change.newValue != null && (!(change.newValue is double) || !change.newValue.isNaN))) {
        final PaperInputDecorator jobNumber = $['jobNumber'];
        jobNumber.isInvalid = false;
      } else if (change.name == #name && (change.newValue == null || change.newValue == '')) {
        final PaperInputDecorator name = $['name'];
        name.isInvalid = true;
      } else if (change.name == #name && (change.newValue != null && change.newValue != '')) {
        final PaperInputDecorator name = $['name'];
        name.isInvalid = false;
      }
    }
  }

  // TODO: implement backgroundImage
  @override
  String get backgroundImage => null;

  @override
  void fabAction() {
    putProjectData(project.json);
  }

  void putProjectData(Map data) {
    if (fetch == null) {
      final _request = new HttpRequest();
      _request.open('PUT', '/a_la_carte/${data["id"]}');
      _request.setRequestHeader('Accept', 'application/json');

      _request.send();
    } else {
      fetch('/a_la_carte/${data["id"]}',
          method: 'PUT', headers: {'Content-Type': 'application/json'},
          body: JSON.encode(project.jsonGetter()));
    }
  }
}
