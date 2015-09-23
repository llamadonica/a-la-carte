library a_la_carte.client.a_la_carte_search_page;

import 'package:core_elements/core_input.dart';
import 'package:polymer/polymer.dart';
import 'package:a_la_carte/a_la_carte_page_common.dart';
import 'package:a_la_carte/models.dart';

/**
 * A Polymer a-la-carte-search-page element.
 */
@CustomTag('a-la-carte-search-page')
class ALaCarteSearchPage extends ALaCartePageCommon {
  @published CoreInput searchInput;
  @published String searchText;
  @published Presenter appPresenter;
  @observable bool isSearching = true;

  /// Constructor used to create instance of ALaCarteSearchPage.
  ALaCarteSearchPage.created() : super.created() {}

  /*
   * Optional lifecycle methods - uncomment if needed.
   *

  /// Called when an instance of a-la-carte-search-page is inserted into the DOM.
  attached() {
    super.attached();
  }

  /// Called when an instance of a-la-carte-search-page is removed from the DOM.
  detached() {
    super.detached();
  }

  /// Called when an attribute (such as  a class) of an instance of
  /// a-la-carte-search-page is added, changed, or removed.
  attributeChanged(String name, String oldValue, String newValue) {
  }

  /// Called when a-la-carte-search-page has been fully prepared (Shadow DOM created,
  /// property observers set up, event listeners attached).
  ready() {
  }

  */

  // TODO: implement backgroundImage
  @override
  String get backgroundImage => null;

  @override
  void fabAction() {}
}
