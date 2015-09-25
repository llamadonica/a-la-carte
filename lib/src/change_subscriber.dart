library  a_la_carte.server.change_subscriber;

import 'dart:async';

import 'package:d17/d17.dart';

import 'db_backend.dart';
import 'search_backend.dart';

abstract class ChangeSubscriberIsolate  {
  void listen();
  ChangeSubscriberIsolate() : super();
}

class ChangeSubscriberIsolateImpl extends ChangeSubscriberIsolate {
  @inject
  DbBackend _dbConnection;

  //@inject
  SearchBackend _searchBackend;

  void listen() {
    Future listenInternal() async {

      await for (var change in _dbConnection.subscribeToChanges('a_la_carte')) {

      }
    }
    print('${new DateTime.now()}\tListening for changes...');
    listenInternal();
  }

  ChangeSubscriberIsolateImpl() : super() {}
}