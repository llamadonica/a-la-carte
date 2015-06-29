library a_la_carte.fetch_interop;

import 'dart:async';
import 'dart:typed_data';
import 'dart:js';

enum RequestContext {
  none,
  audio,
  beacon,
  cspreport,
  download,
  embed,
  eventsource,
  favicon,
  fetch,
  font,
  form,
  frame,
  hyperlink,
  iframe,
  image,
  imageset,
  import,
  internal,
  location,
  manifest,
  metarefresh,
  object,
  ping,
  plugin,
  prefetch,
  preload,
  prerender,
  script,
  sharedworker,
  subresource,
  style,
  track,
  video,
  worker,
  xmlhttprequest,
  xslt
}

String enumToString(t) {
  var regex = new RegExp('[A-Z]');
  var i = 0;
  var buffer = new StringBuffer();
  var rawString = t.toString().split('.')[1];
  regex.allMatches(rawString).forEach((match) {
    buffer.write(rawString.substring(i, match.start - 1));
    buffer.write('-');
    buffer.write(match.group(0).toLowerCase());
    i = match.end;
  });
  buffer.write(rawString.substring(i));
  return buffer.toString();
}

enum RequestMode { sameOrigin, noCors, cors }
enum RequestCredentials { omit, sameOrigin, include }
enum RequestCache {
  defaultCache,
  noStore,
  reload,
  noCache,
  forceCache,
  onlyIfCached
}
enum RequestRedirect { follow, error, manual }

JsFunction get _fetch => context['fetch'];

typedef Future<Response> Fetcher(String url, {String method,
    Map<String, Object> headers, Object body, RequestMode mode,
    RequestCredentials credentials, RequestCache cache,
    RequestRedirect redirect});

Fetcher get fetch => _fetch == null ? null : fetch_internal;

Future<Response> fetch_internal(String url, {String method,
    Map<String, Object> headers, Object body, RequestMode mode,
    RequestCredentials credentials, RequestCache cache,
    RequestRedirect redirect}) {
  Map options = {};
  if (method != null) {
    options['method'] = method;
  }
  if (headers != null) {
    options['headers'] = headers;
  }
  if (body != null) {
    options['body'] = body;
  }
  if (mode != null) {
    options['mode'] = enumToString(mode);
  }
  if (credentials != null) {
    options['credentials'] = enumToString(credentials);
  }
  if (cache != null) {
    options['cache'] = enumToString(cache);
  }
  if (redirect != null) {
    options['redirect'] = enumToString(redirect);
  }
  var completer = new Completer<Response>();
  JsObject promise = _fetch.apply([url, new JsObject.jsify(options)]);
  promise.callMethod('then', [
    (JsObject object) => completer.complete(new Response._internal(object)),
    (object) => completer.completeError(object)
  ]);
  return completer.future;
}

class Response {
  final JsObject _jsObject;
  Response._internal(JsObject this._jsObject);
  ReadableByteStream get body =>
      new ReadableByteStream._internal(_jsObject['body']);
  bool get bodyUsed => _jsObject['bodyUsed'];
  int get status => _jsObject['status'];
  String get statusText => _jsObject['statusText'];
  String get type => _jsObject['type'];
  String get url => _jsObject['url'];
  JsObject get headers => _jsObject['headers'];
}

class ReadableByteStream {
  final JsObject _jsObject;
  ReadableByteStream._internal(JsObject this._jsObject);

  void cancel([String reason]) =>
      _jsObject.callMethod('cancel', reason == null ? [] : [reason]);
  ReadableByteStreamReader getReader() =>
      new ReadableByteStreamReader._internal(_jsObject.callMethod('getReader'));
}

class ReadableByteStreamReaderReadResult {
  final bool done;
  final Uint8List value;
  ReadableByteStreamReaderReadResult(bool this.done, Uint8List this.value);
}

class ReadableByteStreamReader {
  final JsObject _jsObject;
  ReadableByteStreamReader._internal(JsObject this._jsObject);
  Future<ReadableByteStreamReaderReadResult> read() {
    var completer = new Completer<ReadableByteStreamReaderReadResult>();
    JsObject promise = _jsObject.callMethod('read');
    promise.callMethod('then', [
      (JsObject object) => completer.complete(
          new ReadableByteStreamReaderReadResult(
              object['done'], object['value'])),
      (object) => completer.completeError(object)
    ]);
    return completer.future;
  }
  Future cancel() {
    var completer = new Completer();
    JsObject promise = _jsObject.callMethod('cancel');
    promise.callMethod('then', [
      (JsObject _) => completer.complete(),
      (object) => completer.completeError(object)
    ]);
    return completer.future;
  }
}
