library search_provider;

import 'dart:async';
import 'dart:html';
import 'package:polymer/polymer.dart';

/**
 * A Polymer search-provider element.
 */
@CustomTag('search-provider')
class SearchProvider extends PolymerElement {
  static const _onSearchProviderResult =
      const EventStreamProvider('search-provider-result');
  static const _onSearchProviderError =
      const EventStreamProvider('search-provider-error');

  @published bool autosearch = false;
  @published int autosearchDelay = 500;
  @published String searchUrl;
  @published String searchText;

  HttpRequest _httpRequest;
  Timer _autosearchTimer;

  /// Constructor used to create instance of SearchProvider.
  SearchProvider.created() : super.created() {}

  void autosearchChanged(bool oldValue) {
    if (autosearch == true && oldValue != true && searchText != null) {
      _autosearchTimer =
          new Timer(new Duration(milliseconds: autosearchDelay), _timerTimeOut);
    } else if (autosearch == false && _autosearchTimer != null) {
      _autosearchTimer.cancel();
    }
  }

  void autoseachDelayChanged(int oldValue) {
    if (autosearch == true && searchText != null) {
      if (_autosearchTimer != null) {
        _autosearchTimer.cancel();
      }
      _autosearchTimer =
          new Timer(new Duration(milliseconds: autosearchDelay), _timerTimeOut);
    }
  }

  void searchTextChanged(String oldValue) {
    if (autosearch == true) {
      if (_autosearchTimer != null) {
        _autosearchTimer.cancel();
      }
      _autosearchTimer =
          new Timer(new Duration(milliseconds: autosearchDelay), _timerTimeOut);
    }
  }

  Stream<CustomEvent> get onSearchProviderResult =>
      _onSearchProviderResult.forElement(this);
  Stream<CustomEvent> get onSearchProviderError =>
      _onSearchProviderError.forElement(this);

  void _timerTimeOut() => search();

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
    if (searchText == null) return;
    if (_httpRequest != null) {
      _httpRequest.abort();
    }
    var searchComponent = Uri.encodeQueryComponent(searchText);
    var sendUrl = searchUrl + '?' + searchComponent;

    _httpRequest = new HttpRequest();
    _httpRequest.responseType = 'json';
    _httpRequest.onLoad.first.then(_onSearchResult);
    _httpRequest.onError.first.then(_onSearchError);
    _httpRequest.open('GET', sendUrl);
    _httpRequest.setRequestHeader('accept', 'application/json');
    _httpRequest.send();
  }

  void _onSearchResult(ProgressEvent e) {
    if (_httpRequest.status != 200) {
      fire('search-provider-error', detail: _httpRequest.response);
    } else {
      fire('search-provider-result', detail: _httpRequest.response);
    }
    _httpRequest = null;
  }

  void _onSearchError(ProgressEvent value) {
    fire('search-provider-error',
        detail: {'error': 0, 'readyState': _httpRequest.readyState});
    _httpRequest = null;
  }
}
