// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library a_la_carte;

import 'dart:io';

import 'package:args/args.dart';

import 'package:a_la_carte/server.dart';

var activeSessions;

void main(List<String> args) {
  var parser = new ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080')
    ..addOption('listeners',
        abbr: 'l', help: 'Number of isolates to spawn', defaultsTo: '3')
    ..addFlag('debug-over-wire',
        help:
            'Send additional debugging information from the server if available.')
    ..addOption('couchPort',
        abbr: 'c',
        help: 'Port for the related CouchDB instance',
        defaultsTo: '5984');

  var result = parser.parse(args);

  var port = int.parse(result['port'], onError: (val) {
    stdout.writeln('Could not parse port value "$val" into a number.');
    exit(1);
  });
  var couchPort = int.parse(result['couchPort'], onError: (val) {
    stdout.writeln('Could not parse couchPort value "$val" into a number.');
    exit(1);
  });
  var listeners = int.parse(result['listeners'], onError: (val) {
    stdout.writeln('Could not parse listeners value "$val" into a number.');
    exit(1);
  });
  var debugOverWire = result['debug-over-wire'];

  var server =
      new Server(port, couchPort, listeners, debugOverWire: debugOverWire);

  ProcessSignal.SIGINT.watch().listen((sig) {
    print('Got SIGINT');
    exit(0);
  });

  if (!Platform.isWindows) {
    ProcessSignal.SIGTERM.watch().listen((sig) {
      print('Got SIGTERM');
      exit(0);
    });
  }

  server.serve();
}
