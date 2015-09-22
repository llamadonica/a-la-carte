library a_la_carte.client.google_map;

import 'dart:async';
import 'dart:html';
import 'dart:js';

import 'package:google_maps/google_maps.dart' hide Animation, MouseEvent;
import 'package:google_maps/google_maps.dart' as google_maps;
import 'package:core_elements/core_icon.dart';
import 'package:polymer/polymer.dart';

@CustomTag('google-map')
class GoogleMap extends PolymerElement {
  @published double latitude;
  @published double longitude;
  @published double zoom;
  @published Map config;
  @published String placeId;
  @published bool pinHasMovedFromPlace;
  @published String address;

  @observable bool addressIsSet;

  GMap map;

  Marker _placeMarker;
  LatLngBounds _placeMarkerBounds;
  double _placeMarkerLatDiff;
  String _geolocationAddress;
  InfoWindow _infoWindowPopup;

  Geocoder geocoder;
  bool _placeIdChangeExpected = false;

  var defaultLatitude = 0;
  var defaultLongitude = 0;
  var defaultZoom = 0;

  placeIdChanged(String oldPlaceId) {
    if (_placeIdChangeExpected) {
      _placeIdChangeExpected = false;
      return;
    }
    Future _asyncPart() async {
      await mapsApiLoaded;
      if (!addressIsSet && placeId != null) {
        map.streetView.visible = false;
        _setPlace(placeId);
      } else if (placeId == null &&
          (oldPlaceId != null || pinHasMovedFromPlace)) {
        map.streetView.visible = false;
        _resetPlace();
      }
    }
    _asyncPart();
  }

  configChanged(Map oldValue) {
    if (oldValue != null) {
      throw new StateError(
          "Map configuration can't be changed once the map api is loaded.");
    }
    final script = new ScriptElement()
      ..id = 'google-maps-api'
      ..defer = true
      ..async = true
      ..src =
          'https://maps.googleapis.com/maps/api/js?key=${config["apis"]["googleApiKey"]}&callback=initMap';

    document.head.append(script);

    defaultLatitude = config['map']['defaultLatitude'];
    defaultLongitude = config['map']['defaultLongitude'];
    defaultZoom = config['map']['defaultZoomLevel'];
  }

  _headMutated(List<MutationRecord> records, MutationObserver _) {
    for (var record in records) {
      for (var node in record.addedNodes) {
        if (node is! StyleElement) continue;
        String styleText = node.innerHtml;
        if (styleText.startsWith('@-webkit-keyframes')) {
          var nodeToInsert = new StyleElement()
            ..type = 'text/css'
            ..innerHtml = styleText +
                r'''

  img[src="https://maps.gstatic.com/mapfiles/api-3/images/spotlight-poi.png"] {
    opacity: 1.0;
  }
''';
          shadowRoot.append(nodeToInsert);
        }
      }
    }
  }

  GoogleMap.created() : super.created() {}

  attached() {
    super.attached();
    new MutationObserver(_headMutated)..observe(document.head, childList: true);
    _initializeMap();
  }

  Future _initializeMap() async {
    await mapsApiLoaded;
    var latLng;
    var zoomLevel;
    if (latitude == null) {
      latLng = new LatLng(defaultLatitude, defaultLongitude);
      zoomLevel = defaultZoom;
    } else {
      latLng = new LatLng(latitude, longitude);
      zoomLevel = defaultZoom;
    }
    final mapOptions = new MapOptions()
      ..mapTypeId = MapTypeId.ROADMAP
      ..center = latLng
      ..zoom = zoomLevel;
    final mapView = $['map'];
    map = new GMap(mapView, mapOptions);
    _setUpAdditionalControls(map);
    map
      ..onZoomChanged.listen((_) {
        zoom = map.zoom;
      })
      ..onRightclick.listen(_rightClickOnMap);
    geocoder = new Geocoder();

    // this allow to notify the map that the size of the canvas has changed.
    // in some cases, the map behaves like it has a 0*0 size.
    event.trigger(map, 'resize', []);
  }

  void _setUpAdditionalControls(GMap map) {
    var recenterButton = new DivElement()
      ..classes.add('control-button')
      ..classes.add('control-button-left')
      ..innerHtml = 'Recenter'
      ..onClick.listen(_recenterMap);
    var geolocationIcon = new CoreIcon()..icon = 'device:gps-fixed';
    var geolocationButton = new DivElement()
      ..classes.add('control-button')
      ..classes.add('control-button-right')
      ..append(geolocationIcon)
      ..onClick.listen(_geolocateMe);
    var controlUi = new DivElement()
      ..classes.add('control-container')
      ..append(recenterButton)
      ..append(geolocationButton);
    map.controls[ControlPosition.TOP_CENTER].push(controlUi);
  }

  void _recenterMap(MouseEvent event) {
    if (_placeMarker != null) {
      map.fitBounds(_placeMarkerBounds);
    }
  }

  void _geolocateMe(MouseEvent event) {
    Future _geolocateMeAsync() async {
      var geoposition = await window.navigator.geolocation.getCurrentPosition(
          enableHighAccuracy: true, timeout: new Duration(seconds: 5));
      latitude = geoposition.coords.latitude;
      longitude = geoposition.coords.longitude;
      await setPlaceIdFromLatitudeAndLongitude(
          setInfo: true, relocatePin: true);
    }
    _geolocateMeAsync();
  }

  _clearPlaceMarker({bool clearOldPlace: false}) {
    if (_placeMarker != null) {
      _placeMarker.map = null;
      _placeMarker = null;
    }
    if (_infoWindowPopup != null) {
      _infoWindowPopup.close();
      _infoWindowPopup = null;
    }
    if (clearOldPlace) {
      addressIsSet = false;
      _placeIdChangeExpected = true;
      placeId = null;
      latitude = null;
      longitude = null;
    }
  }

  Future _resetPlace() {
    _clearPlaceMarker();
    latitude = null;
    longitude = null;
    addressIsSet = false;
    return resetToInitialState();
  }

  Future resetToInitialState() async {
    await mapsApiLoaded;
    var latLng;
    var zoomLevel;
    if (latitude == null) {
      latLng = new LatLng(defaultLatitude, defaultLongitude);
      zoomLevel = defaultZoom;
    } else {
      latLng = new LatLng(latitude, longitude);
      zoomLevel = defaultZoom;
    }
    map
      ..center = latLng
      ..zoom = zoomLevel;
  }

  Future _setPlace(String place_) async {
    final completer = new Completer();
    final geocodeRequest = new GeocoderRequest()..$unsafe['placeId'] = place_;
    await mapsApiLoaded;
    geocoder.geocode(geocodeRequest,
        (List<GeocoderResult> results, GeocoderStatus status) {
      if (status == GeocoderStatus.OK) {
        final GeocoderResult result = results[0];
        _setPlaceMarker(result);
        completer.complete(placeId);
      } else {
        completer.completeError(new ArgumentError('Could not find location'));
      }
    });
    return await completer.future;
  }

  _setPlaceInfo(GeocoderResult result, {bool setPlaceIdFromResult: false}) {
    if (setPlaceIdFromResult) {
      _placeIdChangeExpected = true;
      placeId = result.$unsafe['place_id'];
    }
    latitude = result.geometry.location.lat;
    longitude = result.geometry.location.lng;
    _placeMarkerLatDiff =
        _placeMarkerBounds.northEast.lat - _placeMarkerBounds.southWest.lat;

    addressIsSet = true;
    _geolocationAddress = result.formattedAddress;

    pinHasMovedFromPlace = false;
  }

  _setPlaceMarker(GeocoderResult result,
      {bool fitBounds: true, bool setPlaceId: false}) {
    if (fitBounds) {
      map.fitBounds(_placeMarkerBounds = result.geometry.viewport);
    }

    _setPlaceInfo(result, setPlaceIdFromResult: setPlaceId);
    final markerOptions = new MarkerOptions()
      ..map = map
      ..raiseOnDrag = true
      ..animation = google_maps.Animation.DROP
      ..draggable = true
      ..position = result.geometry.location;
    _clearPlaceMarker();
    _placeMarker = new Marker(markerOptions)
      ..onDragstart
          .listen((_) => _placeMarker.$unsafe.callMethod('setAnimation', [3]))
      ..onDragend.listen((_) {
        _placeMarker.$unsafe.callMethod('setAnimation', [4]);
        latitude = _placeMarker.position.lat;
        longitude = _placeMarker.position.lng;
        pinHasMovedFromPlace = true;
        _placeMarkerBounds = new LatLngBounds(
            new LatLng(latitude - _placeMarkerLatDiff / 2,
                longitude - _placeMarkerLatDiff / 2),
            new LatLng(latitude + _placeMarkerLatDiff / 2,
                longitude + _placeMarkerLatDiff / 2));
        _placeIdChangeExpected = true;
        placeId = null;
      })
      ..onClick.listen((_) {
        _createInfoPage().then((infoNode) {
          var options = new InfoWindowOptions()..content = infoNode;
          if (_infoWindowPopup != null) {
            _infoWindowPopup.close();
          }
          _infoWindowPopup = new InfoWindow(options);
          _infoWindowPopup.open(map, _placeMarker);
        });
      });
  }

  Future setAddress(String address_) {
    final completer = new Completer();
    final geocodeRequest = new GeocoderRequest()
      ..address = address_
      ..bounds = map.bounds;
    geocoder.geocode(geocodeRequest,
        (List<GeocoderResult> results, GeocoderStatus status) {
      if (status == GeocoderStatus.OK) {
        final GeocoderResult result = results[0];
        _setPlaceMarker(result, setPlaceId: true);
        completer.complete(placeId);
      } else {
        completer.completeError(new ArgumentError('Could not find location'));
      }
    });
    return completer.future;
  }

  Future<String> setPlaceIdFromLatitudeAndLongitude(
      {bool setInfo: false,
      bool relocatePin: false,
      bool fitBounds: true}) async {
    await mapsApiLoaded;
    final completer = new Completer<String>();
    final geocodeRequest = new GeocoderRequest()
      ..location = new LatLng(latitude, longitude);
    geocoder.geocode(geocodeRequest,
        (List<GeocoderResult> results, GeocoderStatus status) {
      if (status == GeocoderStatus.OK) {
        window.console.log('Got a specific place.');
        final GeocoderResult result = results[0];
        completer.complete(result.$unsafe['place_id']);
        pinHasMovedFromPlace = false;
        if (relocatePin) {
          _setPlaceMarker(result, fitBounds: fitBounds, setPlaceId: setInfo);
        } else if (setInfo) {
          _setPlaceInfo(result, setPlaceIdFromResult: true);
        }
      } else {
        window.console.log('Could not get a specific place.');
        completer.completeError(new ArgumentError('Could not find location'));
      }
    });
    return await completer.future;
  }

  Future<Node> _createInfoPage() async {
    if (pinHasMovedFromPlace) {
      await setPlaceIdFromLatitudeAndLongitude(setInfo: true);
    }
    final infoDiv = new DivElement()
      ..classes.add('info-address')
      ..innerHtml = this._geolocationAddress;
    final addressButton = new AnchorElement()
      ..href = '#'
      ..innerHtml = 'Set address to this location'
      ..onClick.listen(_setProjectAddressToThis);
    final clearButton = new AnchorElement()
      ..href = '#'
      ..innerHtml = 'Delete pin'
      ..onClick.listen(_deletePin);
    final addressButtonDiv = new DivElement()
      ..classes.add('info-button')
      ..append(addressButton);
    final clearButtonDiv = new DivElement()
      ..classes.add('info-button')
      ..append(clearButton);
    final allButtons = new DivElement()
      ..classes.add('info-buttons')
      ..append(addressButtonDiv)
      ..append(clearButtonDiv);
    final popup = new DivElement()
      ..classes.add('info-popup')
      ..append(infoDiv)
      ..append(allButtons);
    return popup;
  }

  Node _createDropDialog(LatLng location) {
    final dropButton = new AnchorElement()
      ..href = '#'
      ..innerHtml = 'Drop pin'
      ..onClick.listen((_) => _newPin(location));
    final dropButtonDiv = new DivElement()
      ..classes.add('info-button')
      ..append(dropButton);
    final popup = new DivElement()
      ..classes.add('info-popup')
      ..append(dropButtonDiv);
    return popup;
  }

  void _newPin(LatLng location) {
    latitude = location.lat;
    longitude = location.lng;
    setPlaceIdFromLatitudeAndLongitude(
        setInfo: true, relocatePin: true, fitBounds: true);
    _infoWindowPopup.close();
    _infoWindowPopup = null;
  }

  Future _mapsApiLoaded;
  Future get mapsApiLoaded {
    if (_mapsApiLoaded == null) {
      var completer = new Completer();
      JsObject mapsApiPromise = context['mapsApiPromise'];
      mapsApiPromise.callMethod('then', [
        (_) {
          completer.complete();
        }
      ]);
      _mapsApiLoaded = completer.future;
    }
    return _mapsApiLoaded;
  }

  void _deletePin(MouseEvent event) {
    _clearPlaceMarker(clearOldPlace: true);
    event.preventDefault();
  }

  void _rightClickOnMap(google_maps.MouseEvent mouseEvent) {
    if (addressIsSet) return;
    var options = new InfoWindowOptions()
      ..content = _createDropDialog(mouseEvent.latLng)
      ..position = mouseEvent.latLng;
    if (_infoWindowPopup != null) {
      _infoWindowPopup.close();
    }
    _infoWindowPopup = new InfoWindow(options);
    _infoWindowPopup.open(map, _placeMarker);
  }

  void _setProjectAddressToThis(MouseEvent event) {
    address = _geolocationAddress;
    event.preventDefault();
  }
}
