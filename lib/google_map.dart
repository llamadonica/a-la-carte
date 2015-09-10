import 'dart:async';
import 'dart:html';
import 'dart:js';

import 'package:google_maps/google_maps.dart' hide Animation;
import 'package:google_maps/google_maps.dart' as google_maps;
import 'package:polymer/polymer.dart';

@CustomTag('google-map')
class GoogleMap extends PolymerElement {
  @published double latitude;
  @published double longitude;
  @published double zoom;
  @published Map config;
  @published String placeId;

  @observable bool addressIsSet;
  @observable String address;
  GMap map;
  Marker _placeMarker;
  Geocoder geocoder;
  MutationObserver _animationStylingObserver;

  Set _localizedRules = new Set();

  var defaultLatitude = 0;
  var defaultLongitude = 0;
  var defaultZoom = 0;

  placeIdChanged(String oldPlaceId) {
    if (!addressIsSet && placeId != null) {
      setPlace(placeId);
    } else if (placeId == null && oldPlaceId != null) {
      resetPlace();
    }
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
            ..innerHtml = styleText + r'''

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
    _animationStylingObserver = new MutationObserver(_headMutated)
      ..observe(document.head, childList: true);
    initializeMap();
  }

  Future initializeMap() async {
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
    map.onZoomChanged.listen((_) {
      zoom = map.zoom;
    });
    geocoder = new Geocoder();

    // this allow to notify the map that the size of the canvas has changed.
    // in some cases, the map behaves like it has a 0*0 size.
    event.trigger(map, 'resize', []);
  }

  Future resetPlace() async {
    if (_placeMarker != null) {
      _placeMarker.map = null;
    }
    latitude = null;
    longitude = null;
    addressIsSet = false;
    await resetToInitialState();
  }

  Future resetToInitialState() async {
    await mapsApiLoaded;
    var latLng;
    var zoomLevel;
    if (latitude == null) {
      latLng = new LatLng(38.5556, -121.4689);
      zoomLevel = 8;
    } else {
      latLng = new LatLng(latitude, longitude);
      zoomLevel = 14;
    }
    map
      ..center = latLng
      ..zoom = zoomLevel;
  }

  Future setPlace(String place_) async {
    final completer = new Completer();
    final geocodeRequest = new GeocoderRequest()..$unsafe['placeId'] = place_;
    await mapsApiLoaded;
    geocoder.geocode(geocodeRequest,
        (List<GeocoderResult> results, GeocoderStatus status) {
      if (status == GeocoderStatus.OK) {
        final GeocoderResult result = results[0];
        map.fitBounds(result.geometry.viewport);
        placeId = result.$unsafe['place_id'];
        latitude = result.geometry.location.lat;
        longitude = result.geometry.location.lng;
        addressIsSet = true;
          final markerOptions = new MarkerOptions()
            ..map = map
            ..raiseOnDrag = true
            ..animation = google_maps.Animation.DROP
            ..position = result.geometry.location;
          _placeMarker = new Marker(markerOptions);
        completer.complete(placeId);
      } else {
        completer.completeError(new ArgumentError('Could not find location'));
      }
    });
    return await completer.future;
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
        map.fitBounds(result.geometry.viewport);
        placeId = result.$unsafe['place_id'];
        latitude = result.geometry.location.lat;
        longitude = result.geometry.location.lng;
        addressIsSet = true;
        final markerOptions = new MarkerOptions()
            ..map = map
            ..raiseOnDrag = true
            ..animation = google_maps.Animation.DROP
            ..position = result.geometry.location;
          _placeMarker = new Marker(markerOptions);
        completer.complete(placeId);
      } else {
        completer.completeError(new ArgumentError('Could not find location'));
      }
    });
    return completer.future;
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
}
