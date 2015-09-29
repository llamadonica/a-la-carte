library a_la_carte.client.json_streaming;

import 'package:json_stream_parser/json_stream_parser.dart';

class HttpResponseJsonStreamingEvent implements JsonStreamingEvent {
  final JsonStreamingEvent _delegate;
  final int statusCode;
  // TODO: implement boxType
  @override
  JsonStreamingBox get boxType => _delegate.boxType;

  // TODO: implement eventType
  @override
  JsonStreamingEventType get eventType => _delegate.eventType;

  // TODO: implement path
  @override
  List get path => _delegate.path;

  // TODO: implement symbol
  @override
  get symbol => _delegate.symbol;

  HttpResponseJsonStreamingEvent(
      JsonStreamingEvent this._delegate, int this.statusCode);
}
