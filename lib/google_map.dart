import 'dart:async';
import 'dart:js';

import 'package:google_maps/google_maps.dart';
import 'package:polymer/polymer.dart';

@CustomTag('google-map')
class GoogleMap extends PolymerElement {
  @published double latitude;
  @published double longitude;
  @published double zoom;
  @published String placeId;

  @observable bool addressIsSet;
  @observable String address;
  GMap map;
  Geocoder geocoder;

  placeIdChanged(String oldPlaceId) async {
    await mapsApiLoaded;
    if (!addressIsSet && placeId != null) {
      setPlace(placeId);
    } else if (placeId == null && oldPlaceId != null) {
      resetPlace();
    }
  }

  GoogleMap.created() : super.created() {}

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

  Future setPlace(String place_) {
    final completer = new Completer();
    final geocodeRequest = new GeocoderRequest()..$unsafe['placeId'] = place_;
    geocoder.geocode(geocodeRequest,
        (List<GeocoderResult> results, GeocoderStatus status) {
      if (status == GeocoderStatus.OK) {
        final GeocoderResult result = results[0];
        map.fitBounds(result.geometry.viewport);
        placeId = result.$unsafe['place_id'];
        latitude = result.geometry.location.lat;
        longitude = result.geometry.location.lng;
        addressIsSet = true;
        completer.complete(placeId);
      } else {
        completer.completeError(new ArgumentError('Could not find location'));
      }
    });
    return completer.future;
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
