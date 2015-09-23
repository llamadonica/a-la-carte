library search_provider;

import 'dart:html';
import 'package:polymer/polymer.dart';

/**
 * A Polymer search-provider element.
 */
@CustomTag('search-provider')
class SearchProvider extends PolymerElement {
  @published bool autosearch;
  @published int autosearchDelay;
  @published String searchUrl;
  @published String searchText;

  HttpRequest _httpRequest;

  /// Constructor used to create instance of SearchProvider.
  SearchProvider.created() : super.created() {}

  /*
   * Optional lifecycle methods - uncomment if needed.
   *

  /// Called when an instance of search-provider is inserted into the DOM.
  attached() {
    super.attached();
  }

  /// Called when an instance of search-provider is removed from the DOM.
  detached() {
    super.detached();
  }

  /// Called when an attribute (such as  a class) of an instance of
  /// search-provider is added, changed, or removed.
  attributeChanged(String name, String oldValue, String newValue) {
  }

  /// Called when search-provider has been fully prepared (Shadow DOM created,
  /// property observers set up, event listeners attached).
  ready() {
  }

  */
  void search() {
    if (_httpRequest != null) {
      _httpRequest.abort();
    }
    var searchComponent = Uri.encodeQueryComponent(searchText);
    var sendUrl = searchUrl + '?' + searchComponent;
    _httpRequest = new HttpRequest();
    _httpRequest.responseType;
    _httpRequest.onLoad.first.then(_onSearchResult);
  }

  void _onSearchResult(ProgressEvent e) {
    if (_httpRequest.status != 200) {
      var event = new CustomEvent('search-result-error');
      event.detail = _httpRequest.response;
    }
  }
}
