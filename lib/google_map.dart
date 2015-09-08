import 'dart:async';
import 'dart:js';

import 'package:google_maps/google_maps.dart';
import 'package:polymer/polymer.dart';

@CustomTag('google-map')
class GoogleMap extends PolymerElement {

  @published double latitude;
  @published double longitude;

  @observable bool addressIsSet;
  @observable String address;
  GMap map;
  Geocoder geocoder;

  GoogleMap.created() : super.created() {
  }

  attached() {
    super.attached();
    initializeMap();
  }

  Future initializeMap() async {
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
    final mapOptions = new MapOptions()
      ..mapTypeId = MapTypeId.ROADMAP
      ..center = latLng
      ..zoom = 14;
    final mapView = getShadowRoot('google-map').querySelector("#map");
    map = new GMap(mapView, mapOptions);
    geocoder = new Geocoder();

    // this allow to notify the map that the size of the canvas has changed.
    // in some cases, the map behaves like it has a 0*0 size.
    event.trigger(map, 'resize', []);
  }

  Future setAddress(String address_) {
    final geocodeRequest = new GeocoderRequest()
      ..address = address_;
    geocoder.geocode(geocodeRequest, (List<GeocoderResult> results, GeocoderStatus status) {
    });
  }

  Future _mapsApiLoaded;
  Future get mapsApiLoaded {
    if (_mapsApiLoaded == null ) {
      var completer = new Completer();
      JsObject mapsApiPromise = context['mapsApiPromise'];
      mapsApiPromise.callMethod('then', [(_) {
        completer.complete(); }]);
      _mapsApiLoaded = completer.future;
    }
    return _mapsApiLoaded;
  }
}