library a_la_carte.server;

import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'package:a_la_carte/fetch_interop.dart';

enum JsonStreamingBox { array, object, na }
enum JsonStreamingEvent { open, close, token }

class JsonStreamingEvent {
  final int httpStatus;

  final String statusText;
  final JsonStreamingBox boxType;
  final JsonStreamingEvent eventType;
  final List path;
  final symbol;

  JsonStreamingEvent(JsonStreamingBox this.boxType, Iterable _path,
      dynamic this.symbol, int this.httpStatus, String this.statusText)
      : path = new List.from(_path);

  String toString() {
    var output = new StringBuffer('addJsonStreamingEvent(');
    output.write(boxType);
    output.write(',');
    output.write(path);
    output.write(',');
    output.write(symbol);
    output.write(')');
    return output.toString();
  }
}

//TODO: Rewrite this to make use of the Fetch and Streams API so less of the
//request has to stay resident.
class JsonStreamingParser {
  bool _weAreAtStart = true;
  bool _weAreInObject = false;
  bool _weAreInArray = false;
  bool _weAreInImplicitArray = false;
  bool _isSemiClosed = false;
  bool _requireComma = false;
  bool _requireColon = false;
  bool _requireKey = false;
  int _currentKey = 0;
  String _lastKeyString = null;
  String _lastValueString = null;
  List _currentContexts = new List();
  Object _currentContext;

  List _currentPath;
  final bool _isImplicitArray;

  int _status;
  String _statusText;

  JsonStreamingParser([bool this._isImplicitArray = false]) {
    _weAreInImplicitArray = _isImplicitArray;
    if (_weAreInImplicitArray) {
      _currentPath = [0];
    }
  }

  void httpRequestListener(ProgressEvent event) {
    HttpRequest request = event.currentTarget;

    _status = request.status;
    _statusText = request.statusText;

    String buffer = request.response;
    if (buffer == null) return;
    streamTransform(
        event.loaded, buffer, (buf_, i) => buf_.codeUnitAt(i));
  }

  void httpRequestFinalize(ProgressEvent event) {
    assert(_isSemiClosed);
  }

  void setStreamStateFromResponse(Response response) {
    _status = response.status;
    _statusText = response.statusText;
  }

  void streamFromByteStreamReader(ReadableByteStreamReader reader) {
    var overflowBuffer = new List<int>();
    void streamFromByteStreamReaderInternal() {
      reader.read().then((result) {
        if (result.value == null) {
          assert(_isSemiClosed);
          reader.cancel();
          return;
        }
        this.streamTransform(
            result.value.length,
            result.value,
            (buf_, i) =>
                (i < 0) ? overflowBuffer[overflowBuffer.length + i] : buf_[i]);
        if (_startOfLastSymbol >= 0) {
          overflowBuffer.clear();
        } else {
          overflowBuffer.removeRange(
              0, overflowBuffer.length + _startOfLastSymbol);
          _startOfLastSymbol = 0;
        }
        for (var k = _startOfLastSymbol; k < result.value.length; k++) {
          overflowBuffer.add(result.value[k]);
        }
        _startOfLastSymbol = -overflowBuffer.length;
        if (!result.done) {
          streamFromByteStreamReaderInternal();
        } else {
          assert(_isSemiClosed);
          reader.cancel();
        }
      });
    }
    streamFromByteStreamReaderInternal();
  }

  bool _isWhitespace(int symbol) {
    switch (symbol) {
      case 32:
      case 9:
      case 10:
      case 11:
      case 12:
      case 13:
        return true;
      default:
        return false;
    }
  }

  static Stream<JsonStreamingEvent> streamTransform(Stream<int> symbolBuffer, [bool isImplicitArray = false]) async* {
    final parser = new JsonStreamingParser();
    stateParser: await for (var ch in symbolBuffer) {
      if (_isWhitespace(bufferGetter(buffer, i))) continue;
      if (parser._isSemiClosed) {
        throw new StateError("Expected WHITESPACE");
      }
      if (parser._weAreAtStart && ch == 123) {
        // Open brace {
        if (!parser._weAreInImplicitArray) {
          parser._currentPath = new List();
        } else {
          parser._weAreInImplicitArray = false;
        }
        parser._currentContext = new Map();
        parser._currentContexts.add(_currentContext);

        yield addJsonStreamingEvent(JsonStreamingBox.object, _currentPath, _currentContext);
        parser._weAreAtStart = false;
        parser._weAreInObject = true;
        parser._requireKey = true;
        continue;
      } else if (parser._weAreInImplicitArray) {
        throw new StateError("Expected WHITESPACE or { ");
      } else if (parser._weAreAtStart) {
        parser._parserAssertNotReached("Expected {");
      } else if (parser._weAreInObject &&
          (parser._requireComma || parser._requireKey) &&
          ch == 125) {
        //Close brace }
        yield addJsonStreamingEvent(
            JsonStreamingBox.object, _currentPath, _currentContext);
        if (parser._currentPath.length == 0) {
          parser._isSemiClosed = true;
        } else if (parser._currentPath.length == 1 && parser._isImplicitArray) {
          parser._weAreInObject = false;
          parser._requireComma = false;
          parser._requireKey = false;

          parser._weAreInImplicitArray = true;
          parser._weAreAtStart = true;
          parser._currentPath[0]++;
        } else {
          var lastKey = parser._currentPath.removeLast();
          if (lastKey is int) {
            parser._weAreInObject = false;
            parser._weAreInArray = true;
          } else {
            assert(lastKey is String);
            parser._weAreInObject = true;
            parser._weAreInArray = false;
          }
          parser._requireComma = true;
          parser._currentContexts.removeLast();
          parser._currentContext = parser._currentContexts.last;
        }
        continue;
      } else if (parser._weAreInObject &&
                 parser._requireComma &&
          ch == 44) {
        parser._requireComma = false;
        parser._requireKey = true;
        continue;
      } else if (parser._weAreInObject && parser._requireComma) {
        parser._parserAssertNotReached("Expected } or ,");
      } else if (parser._weAreInObject &&
          parser._requireColon &&
          ch == 58) {
        parser._requireColon = false;
        continue;
      } else if (parser._weAreInObject && parser._requireColon) {
        this._parserAssertNotReached("Expected :");
      } else if (parser._weAreInObject &&
      parser._requireKey &&
          ch == 34) {
        i++;
        i = _parseString(i, loaded, buffer, bufferGetter);
        if (_startOfLastSymbol > i) {
          _lastKeyString = _lastValueString;
          _requireColon = true;
          _requireKey = false;
        }
        continue;
      } else if (_weAreInObject && _requireKey) {
        this._parserAssertNotReached("Expected \" or }");
        continue;
      } else if (_weAreInArray && bufferGetter(buffer, i) == 93) {
        //Close bracket ]
        _onSymbolComplete.add(addJsonStreamingEvent(
            JsonStreamingBox.array, _currentPath, _currentContext));
        _onCloseContainer.add(addJsonStreamingEvent(
            JsonStreamingBox.array, _currentPath, _currentContext));
        var lastKey = _currentPath.removeLast();
        if (lastKey is int) {
          _weAreInObject = false;
          _weAreInArray = true;
        } else {
          assert(lastKey is String);
          _weAreInObject = true;
          _weAreInArray = false;
        }
        _requireComma = true;
        _startOfLastSymbol = i + 1;
        _currentContexts.removeLast();
        _currentContext = _currentContexts.last;
        continue;
      } else if (_weAreInArray &&
          _requireComma &&
          bufferGetter(buffer, i) == 44) {
        _currentKey++;
        _requireComma = false;
      } else if (_weAreInArray && _requireComma) {
        _parserAssertNotReached("Expected ] or ,");
        continue;
        //Now we can accept ANY JSON value.
      } else if (bufferGetter(buffer, i) == 123) {
        // Open brace {
        final tempContext = new Map();
        _currentContexts.add(tempContext);
        if (_weAreInObject) {
          var tempPath = _lastKeyString.toString();
          _currentPath.add(tempPath);
          (_currentContext as Map)[tempPath] = tempContext;
        } else {
          assert(_weAreInArray);
          var tempPath = this._currentKey;
          _currentPath.add(tempPath);
          (_currentContext as List).add(tempContext);
        }
        _currentContext = tempContext;
        _onOpenContainer.add(addJsonStreamingEvent(
            JsonStreamingBox.object, _currentPath, _currentContext));
        _weAreAtStart = false;
        _weAreInObject = true;
        _weAreInArray = false;
        _requireKey = true;
        _lastKeyString = null;
        _startOfLastSymbol = i + 1;
        continue;
      } else if (bufferGetter(buffer, i) == 91) {
        // Open bracket [
        final tempContext = new List();
        _currentContexts.add(tempContext);
        if (_weAreInObject) {
          var tempPath = _lastKeyString.toString();
          _currentPath.add(tempPath);
          (_currentContext as Map)[tempPath] = tempContext;
        } else {
          assert(_weAreInArray);
          var tempPath = this._currentKey;
          _currentPath.add(tempPath);
          (_currentContext as List).add(tempContext);
        }
        _currentContext = tempContext;
        _onOpenContainer.add(addJsonStreamingEvent(
            JsonStreamingBox.array, _currentPath, _currentContext));
        _weAreAtStart = false;
        _weAreInObject = false;
        _weAreInArray = true;
        _currentKey = 0;
        _startOfLastSymbol = i + 1;
        continue;
      } else if (bufferGetter(buffer, i) == 34) {
        // "
        i++;
        i = _parseString(i, loaded, buffer, bufferGetter);

        if (_startOfLastSymbol > i) {
          _makeFinalSymbol(i, _lastValueString);
        }
        continue;
      } else if (bufferGetter(buffer, i) == 116) {
        // t
        if (++i >= loaded) continue;
        // r
        if (!_parserAssert(
            bufferGetter(buffer, i) == 114, "Expected r")) continue;
        if (++i >= loaded) continue;
        // u
        if (!_parserAssert(
            bufferGetter(buffer, i) == 117, "Expected u")) continue;
        if (++i >= loaded) continue;
        // e
        if (!_parserAssert(
            bufferGetter(buffer, i) == 101, "Expected e")) continue;
        _makeFinalSymbol(i, true);
        continue;
      } else if (bufferGetter(buffer, i) == 102) {
        // f
        if (++i >= loaded) continue;
        // a
        if (!_parserAssert(
            bufferGetter(buffer, i) == 97, "Expected a")) continue;
        if (++i >= loaded) continue;
        // l
        if (!_parserAssert(
            bufferGetter(buffer, i) == 108, "Expected l")) continue;
        if (++i >= loaded) continue;
        // s
        if (!_parserAssert(
            bufferGetter(buffer, i) == 115, "Expected s")) continue;
        if (++i >= loaded) continue;
        // e
        if (!_parserAssert(
            bufferGetter(buffer, i) == 101, "Expected e")) continue;
        _makeFinalSymbol(i, false);
        _startOfLastSymbol = i + 1;
        continue;
      } else if (bufferGetter(buffer, i) == 110) {
        // n
        if (++i >= loaded) continue;
        // a
        if (!_parserAssert(
            bufferGetter(buffer, i) == 117, "Expected u")) continue;
        if (++i >= loaded) continue;
        // l
        if (!_parserAssert(
            bufferGetter(buffer, i) == 108, "Expected l")) continue;
        if (++i >= loaded) continue;
        // l
        if (!_parserAssert(
            bufferGetter(buffer, i) == 108, "Expected l")) continue;
        _makeFinalSymbol(i, null);
        continue;
      } else if (<int>[45, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57]
          .contains(bufferGetter(buffer, i))) {
        final valueString = new StringBuffer();
        valueString.writeCharCode(bufferGetter(buffer, i));
        if (bufferGetter(buffer, i) == 45) {
          if (++i >= loaded) continue;
          if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57]
              .contains(bufferGetter(buffer, i))) {
            valueString.writeCharCode(bufferGetter(buffer, i));
          } else {
            _parserAssertNotReached("DIGIT");
          }
        }
        //We are queued up at the first digit.
        bool hasHadDecimal = false;
        bool hasHadExponent = false;
        ++i;
        while (i < loaded) {
          //We need at LEAST
          if (this._isWhitespace(bufferGetter(buffer, i)) ||
              <int>[44, 93, 125].contains(bufferGetter(buffer, i))) {
            if (hasHadDecimal) {
              var value = double.parse(valueString.toString());
              _makeFinalSymbol(i - 1, value);
            } else {
              var value = int.parse(valueString.toString());
              _makeFinalSymbol(i - 1, value);
            }
            i = i - 1;
            continue stateParser;
          } else if (!hasHadDecimal && bufferGetter(buffer, i) == 46) {
            valueString.writeCharCode(bufferGetter(buffer, i));
            hasHadDecimal = true;
            i++;
            continue;
          } else if (bufferGetter(buffer, i) == 46) {
            if (!hasHadExponent) {
              _parserAssertNotReached('Expected digit or e');
            } else {
              _parserAssertNotReached('Expected digit');
            }
            i++;
            continue stateParser;
          } else if (!hasHadExponent &&
              (bufferGetter(buffer, i) == 46 ||
                  bufferGetter(buffer, i) == 101)) {
            // E / e
            valueString.writeCharCode(bufferGetter(buffer, i));
            if (++i >= loaded) continue stateParser;
            if (bufferGetter(buffer, i) == 45 ||
                bufferGetter(buffer, i) == 43) {
              valueString.writeCharCode(bufferGetter(buffer, i));
              if (++i >= loaded) continue stateParser;
              if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57]
                  .contains(bufferGetter(buffer, i))) {
                valueString.writeCharCode(bufferGetter(buffer, i));
              } else {
                _parserAssertNotReached("Expected DIGIT");
                continue stateParser;
              }
            } else if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57]
                .contains(bufferGetter(buffer, i))) {
              valueString.writeCharCode(bufferGetter(buffer, i));
            } else {
              _parserAssertNotReached("Expected DIGIT, +, or -");
              continue stateParser;
            }
            hasHadExponent = true;
            hasHadDecimal = true;
            i++;
            continue;
          } else if (bufferGetter(buffer, i) == 46 ||
              bufferGetter(buffer, i) == 101) {
            _parserAssertNotReached('Expected digit');
            continue stateParser;
          } else if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57]
              .contains(bufferGetter(buffer, i))) {
            valueString.writeCharCode(bufferGetter(buffer, i));
            i++;
            continue;
          } else {
            _parserAssertNotReached("Expected DIGIT, e, E, or .");
            continue stateParser;
          }
        }
      } else {
        _parserAssertNotReached(
            "Expected {, [, \", -, DIGIT, WHITESPACE, null, true, or false");
      }
    }
  }

  static JsonStreamingEvent addJsonStreamingEvent(JsonStreamingBox object,
          List currentPath, Object currentContext) =>
      new JsonStreamingEvent(
          object, currentPath, currentContext, _status, _statusText);

  void _parserAssertNotReached(String message) {
    throw new StateError(message);
    _isSemiClosed = true;
  }

  void _makeFinalSymbol(int i, value) {
    if (_weAreInObject) {
      var tempPath = _lastKeyString.toString();
      _currentPath.add(tempPath);
      (_currentContext as Map)[tempPath] = value;
    } else {
      assert(_weAreInArray);
      var tempPath = this._currentKey;
      _currentPath.add(tempPath);
      (_currentContext as List).add(value);
    }
    _onSymbolComplete.add(addJsonStreamingEvent(
        JsonStreamingBox.na, _currentPath, value));
    _currentPath.removeLast();
    _requireComma = true;
    _startOfLastSymbol = i + 1;
  }

  bool _parserAssert(bool condition, String message) {
    if (!condition) {
      _parserAssertNotReached(message);
    }
    return condition;
  }

  int _parseString(int i, int loaded, buffer, Function bufferGetter) {
    final thisString = new StringBuffer();
    while (i < loaded) {
      if (bufferGetter(buffer, i) == 34) {
        _startOfLastSymbol = i + 1;
        _lastValueString = thisString.toString();
        break;
      } else if (bufferGetter(buffer, i) == 92) {
        i++;
        final int nextBufferCode = bufferGetter(buffer, i);
        if (i >= loaded) return loaded;
        if (nextBufferCode == 34 ||
            nextBufferCode == 92 ||
            nextBufferCode == 47) {
          thisString.writeCharCode(bufferGetter(buffer, i));
        } else {
          switch (nextBufferCode) {
            case 98:
              thisString.writeCharCode(8);
              break;
            case 102:
              thisString.writeCharCode(12);
              break;
            case 110:
              thisString.writeCharCode(10);
              break;
            case 114:
              thisString.writeCharCode(13);
              break;
            case 116:
              thisString.writeCharCode(9);
              break;
            case 117:
              int.parse(
                  new AsciiDecoder().convert([
                    bufferGetter(buffer, i + 1),
                    bufferGetter(buffer, i + 2),
                    bufferGetter(buffer, i + 3),
                    bufferGetter(buffer, i + 4)
                  ]),
                  radix: 16);
              i += 4;
              if (i >= loaded) return loaded;
              break;
            default:
              thisString.writeCharCode(bufferGetter(buffer, i));
          }
        }
        i++;
      } else if (bufferGetter(buffer, i) == 10 ||
          bufferGetter(buffer, i) == 13) {
        _onOpenContainer.addError(new StateError("Expected \" but found EOL"));
        _onCloseContainer.addError(new StateError("Expected \" but found EOL"));
        _onSymbolComplete.addError(new StateError("Expected \" but found EOL"));
        _isSemiClosed = true;
        return loaded;
      } else {
        thisString.writeCharCode(bufferGetter(buffer, i++));
      }
    }
    return i;
  }
}
