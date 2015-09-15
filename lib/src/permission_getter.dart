library a_la_carte.server.permission_getter;

import 'dart:async';
import 'db_backend.dart';

typedef Future<List> RetrievePermissions(
    DbBackend backend, String email, String permissionPath,
    [state]);
