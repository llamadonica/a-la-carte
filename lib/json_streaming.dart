library a_la_carte.client.json_streaming;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:json_stream_parser/json_stream_parser.dart';

import 'package:a_la_carte/fetch_interop.dart';

class HttpResponseJsonStreamingEvent implements JsonStreamingEvent {
  final JsonStreamingEvent _delegate;
  final int httpStatusCode;
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
      JsonStreamingEvent this._delegate, int this.httpStatusCode);
}

const NoBody noBody = const NoBody();

class NoBody {
  const NoBody();
}

class HttpRequestError {
  final int readyState;
  HttpRequestError(this.readyState);
}

class HttpResponseJsonStreamingParser
    extends Stream<HttpResponseJsonStreamingEvent> {
  Stream<HttpResponseJsonStreamingEvent> _delegate;
  bool _gotHeaders = false;
  int _lastCharacter = 0;
  StreamController<int> _characterStream = new StreamController();
  final HttpRequest _request;
  int status;

  HttpResponseJsonStreamingParser.fromHttpRequest(HttpRequest this._request, [bool isImplicitArray = false]) {
    _request.onLoad.listen((event) => _handleProgressEvent(event, true));
    _request.onError.listen(_handleProgressErrorEvent);
    _request.onProgress.listen((event) {
      if (!_gotHeaders && _request.readyState >= 2) {
        _gotHeaders = true;
        status = _request.status;
        if (_request.status == 201) {
          _characterStream.addError(noBody);
        }
      }
      _handleProgressEvent(event);
    });
    _delegate = _characterStream.stream
        .transform(new JsonStreamTransformer(isImplicitArray))
        .map((event) => new HttpResponseJsonStreamingEvent(event, status));
  }

  HttpResponseJsonStreamingParser.fromFetch(Future<Response> fetch, [bool isImplicitArray = false])
      : _request = null {
    fetch.then((response) async {
      if (response.status == 201) {
        _characterStream.addError(noBody);
      }
      status = response.status;
      final reader = response.body.getReader();
      reader.read().then((result) => _handleReaderData(result, reader));
    }, onError: (error) {
      _characterStream.addError(error);
      _characterStream.close();
    });
    _delegate = _characterStream.stream
        .transform(new JsonStreamTransformer(isImplicitArray))
        .map((event) => new HttpResponseJsonStreamingEvent(event, status));
  }

  void _handleProgressEvent(ProgressEvent event, [bool isComplete = false]) {
    if (_request.response == null) return;
    var characterStream = (_request.response as String)
        .substring(_lastCharacter, event.loaded - _lastCharacter);
    _lastCharacter = event.loaded;
    for (var ch in new Utf8Codec().encode(characterStream)) {
      _characterStream.add(ch);
    }
    if (isComplete) {
      _characterStream.close();
    }
  }

  @override
  StreamSubscription<HttpResponseJsonStreamingEvent> listen(
          void onData(HttpResponseJsonStreamingEvent event),
          {Function onError,
          void onDone(),
          bool cancelOnError}) =>
      _delegate.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  _handleReaderData(ReadableByteStreamReaderReadResult value,
      ReadableByteStreamReader reader) {
    if (value.done) {
      _characterStream.close();
      return;
    }
    for (var character in value.value) {
      _characterStream.add(character);
    }
    reader.read().then((result) => _handleReaderData(result, reader));
  }

  void _handleProgressErrorEvent(ProgressEvent event) {
    _characterStream.addError(new HttpRequestError(_request.readyState));
    _characterStream.close();
  }
}
