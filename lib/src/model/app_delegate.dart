part of a_la_carte_models;

abstract class AppDelegate implements AppDelegateIFile {
  int refCount = 0;
  factory AppDelegate() => new HTML5AppDelegate();
  AppDelegate._();
}

abstract class AppDelegateIFile {
  Future<JsonCanSync> getEntity(String id, JsonCanSync entity) =>
      getJson(id).then((map) {
        entity.initFromJSON(map);
        entity.refCount.value = 1;
        return entity;
      });
  Future<Map> getJson(String id, {defaultValue: null});

  Future writeJson(String id, json);
}

class HTML5AppDelegate extends AppDelegate {
  static const MIN_INTERVAL_TO_SAVE = const Duration(seconds: 5);
  html.Storage __storage;
  final Map<String, Future<JsonCanSync>> _entitiesRead = new Map();
  final Map<String, DateTime> _entityTimeouts = new Map();

  final Map<String, Timer> _entityTimers = new Map();

  HTML5AppDelegate() : super._();

  // I'm pushing this up to a Future to make the rewrite easier when I get to
  // writing the Chrome App version.
  Future<html.Storage> get _storage {
    if (__storage == null) __storage = html.window.localStorage;
    return new Future.value(__storage);
  }

  Future<JsonCanSync> getEntity(String id, JsonCanSync entity) {
    if (_entitiesRead.containsKey(id)) {
      return _entitiesRead[id]
        ..then((newEntity) {
          newEntity.refCount.value++;
        });
    }
    entity.refCount.value = 0;
    var entityFuture = getJson(id, defaultValue: {}).then((map) {
      entity.initFromJSON(map);
      entity.refCount.value++;

      this._entitiesRead[id] = new Future.value(entity);

      entity.changes.listen((records) {
        bool repChanged = false;
        entity.isSynced = false;
        for (var record in records) if (record is PropertyChangeRecord &&
            record.name == #json) {
          var timerFunc = () {
            _entityTimers.remove(id);
            _entityTimeouts[id] = new DateTime.now().add(MIN_INTERVAL_TO_SAVE);
            writeJson(id, entity.json).then((_) {
              entity.isSynced = true;
            });
          };
          if (_entityTimeouts.containsKey(id) &&
              !_entityTimers.containsKey(id)) {
            var currentTime = new DateTime.now();

            if (_entityTimeouts[id].isBefore(currentTime)) {
              _entityTimers[id] = new Timer(
                  _entityTimeouts[id].difference(currentTime), timerFunc);
            } else {
              _entityTimers[id] = new Timer(const Duration(), timerFunc);
            }
          } else if (!_entityTimeouts.containsKey(id)) timerFunc();
        }
      });
      return entity;
    });
    _entitiesRead[id] = entityFuture;
    return entityFuture;
  }

  Future<dynamic> getJson(String id, {defaultValue: null}) =>
      _storage.then((storage) {
        return JSON.decode(storage[id]);
      }).catchError((err) {
        if (defaultValue == null) {
          throw err;
        } else {
          return defaultValue;
        }
      });
  Future writeJson(String id, json) => _storage.then((storage) {
        storage[id] = JSON.encode(json);
      }).catchError((err) {
        html.window.console.error(err.message);
        throw err;
      });
}
