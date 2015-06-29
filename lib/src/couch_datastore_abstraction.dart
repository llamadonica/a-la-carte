// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

part of a_la_carte.server;

class CouchDatastoreAbstraction {
  final int port;
  CouchDatastoreAbstraction(int this.port);

  void hijackRequest(Stream<List<int>> input, StreamSink<List<int>> output,
      String method, Uri uri, Map<String, Object> headers) {
    final client = new HttpClient();
    final couchUri = new Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: '127.0.0.1',
        port: port,
        pathSegments: uri.pathSegments,
        queryParameters: uri.queryParameters,
        fragment: uri.fragment);
    client.openUrl(method, couchUri).then((request) {
      for (var header in headers.keys) {
        request.headers.add(header, headers[header]);
      }
      if (method == 'GET' || method == 'HEAD' || method == 'DELETE') {
        request.close();
      }
      input.listen((data) {
        request.add(data);
      }, onDone: () {
        request.close();
      });
      return request.done;
    })
        //TODO: Add the headers from the response.
        .then((HttpClientResponse response) {
      final encoder = new AsciiEncoder();
      output.add(encoder.convert('HTTP/1.1 ${response.statusCode} ${response.reasonPhrase}\r\n'));
      response.headers.forEach((headerName, headerValues) {
        for (var headerValue in headerValues) {
          output.add(encoder.convert('$headerName: $headerValue\r\n'));
        }
      });
      output.add(encoder.convert('Access-Control-Allow-Origin: *\r\n'));
      output.add([13,10]);
      response.listen((data) {
        output.add(encoder.convert('${data.length.toRadixString(16)}\r\n'));
        output.add(data);
        output.add([13,10]);
      }, onDone: () {
        output.add([48,13,10,13,10]);
        print('Closed conection for IO. Isolate: ${Isolate.current.hashCode}');
        output.close();
      }, onError: (error, stackTrace) {
        output.addError(error, stackTrace);
      });
    }).catchError((error, stackTrace) {
      final response = new shelf.Response.internalServerError(
          body: '{"error":"internal_server_error",'
          ' "message": "I couldn\'t connect to the database. Contact your database administrator."}',
          headers: {"Content-Type": "application/json"},
          encoding: Encoding.getByName('identity'));
      final encoder = new Utf8Encoder();
      output.add(encoder.convert('HTTP/1.1 500 Internal Server Error\r\n'));
      response.headers.forEach((headerName, headerValues) {
        if (headerValues is String) {
          output.add(encoder.convert('$headerName: $headerValues\r\n'));
        } else {
          assert(headerValues is List<String>);
          for (var headerValue in headerValues) {
            output.add(encoder.convert('$headerName: $headerValue\r\n'));
          }
        }
      });
      output.add(encoder.convert('Transfer-Encoding: chunked\r\n'));
      output.add(encoder.convert('Access-Control-Allow-Origin: *\r\n'));
      output.add([13,10]);
      response.read().listen((data) {
        output.add(encoder.convert('${data.length.toRadixString(16)}\r\n'));
        output.add(data);
        output.add([13,10]);
      }, onDone: () {
        output.add([48,13,10,13,10]);
        output.close();
      }, onError: (error, stackTrace) {
        output.addError(error, stackTrace);
      });
    });
  }
}
