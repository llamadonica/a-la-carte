import 'dart:html';
import 'dart:math';
import 'dart:async';

import 'package:core_elements/core_animated_pages.dart';
import 'package:paper_elements/paper_button.dart';
import 'package:polymer/polymer.dart';

import '../models.dart';
import 'a_la_carte_page_common.dart';

/**
 * A Polymer click counter element.
 */
@CustomTag('a-la-carte-card-view')
class ALaCarteCardView extends ALaCartePageCommon {
  @published bool wide;
  @published ObservableList<Project> projects;
  @published Project project;
  @published bool projectsAreLoaded;
  @published bool noProjectsFound;
  @observable bool showSpinner = true;

  @published String appSelected;
  @published String prevAppSelected;
  @published AppPager appPager;

  Map<Element, List<Wave>> _waves = new Map<Element, List<Wave>>();

  ALaCarteCardView.created() : super.created() {
    fabIcon = 'add';
  }

  @override void domReady() {
    $['loading-cell'].onTransitionEnd.listen((transition) {
      if (projectsAreLoaded) {
        transition.target.classes.add('hidden');
      } else {
        transition.target.classes.remove('hidden');
        showSpinner = true;
      }
    });
    $['no-projects-cell'].onTransitionEnd.listen((transition) {
      if (noProjectsFound) {
        transition.target.classes.remove('hidden');
      } else {
        transition.target.classes.add('hidden');
      }
    });
  }

  void handleSelect(Event ev) {
    var openCode = (ev.target as PaperButton).getAttribute('data-project-id');
    if (openCode != null) {
      appPager.openProject(openCode);
      (parentNode as CoreAnimatedPages).selected = 'categories';
    }
  }
  void projectsAreLoadedChanged(bool oldValue) {
    if (projectsAreLoaded) {
      showSpinner = false;
      $['loading-cell'].classes.add('hide');
    } else {
      $['loading-cell'].classes.remove('hide');
    }
  }

  void noProjectsFoundChanged(bool oldValue) {
    if (noProjectsFound) {
      $['no-projects-cell'].classes.remove('hide');
    } else {
      $['no-projects-cell'].classes.add('hide');
    }
  }

  @override
  String get backgroundImage => null;

  @override
  void fabAction() {
    appPager.setToNewProject();
    appPager.selected = 1;
  }

  static const double _waveMaxRadius = 150.0;
  static const double _waveInitialOpacity = 0.25;
  static const double _waveOpacityDecayVelocity = 0.8;

  static double _waveMaxDuration(Wave wave) {
    var width = wave.clientWidth.toDouble();
    var height = wave.clientHeight.toDouble();
    var waveRadius =
        min(sqrt(width * width + height * height), _waveMaxRadius) * 1.1 + 5.0;
    var duration = 1.1 - 0.2 * (waveRadius / _waveMaxRadius);
    return duration;
  }

  static double _waveRadiusForTimes(int touchDownMs, int touchUpMs, Wave wave) {
    var width = wave.clientWidth.toDouble();
    var height = wave.clientHeight.toDouble();
    var waveRadius =
        min(sqrt(width * width + height * height), _waveMaxRadius) * 1.1 + 5.0;
    var maxTimeDown =
        log(1 - min(wave.maxRadius, _waveMaxRadius) / waveRadius) / log(80);
    var touchDown = min(-maxTimeDown / 2, touchDownMs.toDouble() / 1000);

    var touchUp = touchUpMs.toDouble() / 1000;
    var totalElapsed = touchDown * 2 + touchUp;
    var duration = _waveMaxDuration(wave);
    var timePortion = totalElapsed / duration;
    var size = waveRadius * (1 - pow(80, -timePortion));
    return size.abs();
  }

  static double _waveOpacityForTimes(int touchUpMs) {
    var touchUp = touchUpMs.toDouble() / 1000;
    if (touchUpMs <= 0) {
      return _waveInitialOpacity;
    }
    var opacity =
        max(0, _waveInitialOpacity - touchUp * _waveOpacityDecayVelocity);
    return opacity;
  }

  static double _waveOuterOpacityForTime(int touchDownMs, int touchUpMs) {
    var touchDown = touchDownMs.toDouble() / 1000;
    var outerOpacity = touchDown * 0.6;
    var waveOpacity = _waveOpacityForTimes(touchUpMs);
    var opacity = max(0, min(outerOpacity, waveOpacity));
    return opacity;
  }

  static bool _waveDidFinish(Wave wave, double radius) {
    var mouseUpMs = wave.mouseUpMs;
    var didFinish = _waveOpacityForTimes(wave.mouseUpMs) < 0.01 &&
        radius >= min(wave.maxRadius, _waveMaxRadius);
    return didFinish;
  }

  static bool _waveAtMaximum(Wave wave, double radius) {
    var mouseUpMs = wave.mouseUpMs;
    var atMaximum =
        wave.mouseUpMs <= 0 && radius >= min(wave.maxRadius, _waveMaxRadius);
    return atMaximum;
  }

  static void _drawRipple(Wave wave, int x, int y, double radius,
      double innerAlpha, double outerAlpha, String waveColor) {
    wave.row.querySelectorAll('.paper-ripple-bg').forEach(
        (DivElement element) => element.style.opacity = outerAlpha.toString());
    var s = radius / (wave.clientSize / 2);
    var dx = x - (wave.clientWidth / 2);
    var dy = y - (wave.clientHeight / 2);
    wave.row
        .querySelectorAll('.paper-ripple-wave')
        .forEach((DivElement element) {
      element.style.opacity = innerAlpha.toString();
      element.style.transform = 'scale3d($s, $s, 1)';
      element.style.color = waveColor;
    });
    wave.row.querySelectorAll('.paper-ripple-wc').forEach((DivElement element) {
      element.style.transform = 'translate3d(${dx}px, ${dy}px, 0)';
    });
  }

  Wave _createWave(DivElement row) {
    var fgColor = row.getComputedStyle().color;
    var wave = new List<Element>();
    var wc = new List<Element>();
    var listener =
        document.onMouseUp.listen((event) => onUpOverEntry(event, row));
    for (DivElement element in row.querySelectorAll('.paper-ripple-bg')) {
      element.style.backgroundColor = fgColor.toString();
    }
    for (DivElement element in row.querySelectorAll('.table-body-cell')) {
      var elementStyle = element.getComputedStyle();
      var inner = document.createElement('div');
      inner.classes.add('paper-ripple-wave');
      var outer = document.createElement('div');
      outer.classes.add('paper-ripple-wc');
      outer.append(inner);
      var container = element.querySelector('.waves');
      container.append(outer);

      wave.add(inner);
      wc.add(outer);
    }
    return new Wave(
        maxRadius: 0.0,
        fgColor: fgColor,
        wave: wave,
        wc: wc,
        row: row,
        listener: listener);
  }

  void _removeFromScope(Wave wave) {
    if (_waves.containsKey(wave.row) && _waves[wave.row].contains(wave)) {
      for (Element el in wave.wc) {
        el.remove();
      }
      wave.listener.cancel();
      _waves[wave.row].remove(wave);
      if (_waves[wave.row].length == 0) {
        _waves.remove(wave.row);
      }
    }
  }

  void onDownOverEntry(MouseEvent event) {
    Element target = event.target;
    var offsetX = 0;
    while (target != null && !target.classes.contains('table-body-row')) {
      if (target.classes.contains('table-body-cell')) {
        offsetX = target.offsetLeft;
      }
      target = target.parent;
    }
    var wave = _createWave(target);
    wave.mouseDownWallClock = new DateTime.now().millisecondsSinceEpoch;
    wave.isMouseDown = true;
    var rectangle = target.client;
    var width = rectangle.width;
    var height = rectangle.height;
    var x = event.offset.x + offsetX - rectangle.left;
    var y = event.offset.y - rectangle.top;
    wave.startPosition = new Point(x, y);
    if (target.classes.contains('recenteringTouch')) {
      wave.endPosition = new Point(rectangle.width / 2, rectangle.height / 2);
      wave.slideDistance = wave.startPosition.distanceTo(wave.endPosition);
    }
    wave.clientSize = max(width, height);
    wave.clientHeight = height;
    wave.clientWidth = width;
    wave.maxRadius = max(max(wave.startPosition.distanceTo(new Point(0, 0)),
        wave.startPosition.distanceTo(new Point(width, 0))), max(
        wave.startPosition.distanceTo(new Point(width, height)),
        wave.startPosition.distanceTo(new Point(0, height))));

    int leftOffset = 0;
    for (Element wc in wave.wc) {
      wc.style.left =
          '${(wave.clientWidth - wave.clientSize) / 2 - leftOffset}px';
      wc.style.top = '${(wave.clientHeight - wave.clientSize) / 2}px';
      wc.style.height = '${wave.clientSize}px';
      wc.style.width = '${wave.clientSize}px';
      leftOffset += wc.parent.client.width;
    }
    for (Element waveDiv in wave.wave) {
      waveDiv.style.backgroundColor = wave.fgColor;
    }
    if (!_waves.containsKey(wave.row)) {
      _waves[wave.row] = <Wave>[];
    }
    _waves[wave.row].add(wave);
    if (_requestedAnimationFrame == null) {
      _requestedAnimationFrame =
          window.requestAnimationFrame((num frame) => _animate());
    }
  }

  void onUpOverEntry(MouseEvent event, Element oldTarget) {
    Element target = oldTarget;
    while (target != null && !target.classes.contains('table-body-row')) {
      target = target.parent;
    }
    for (var wave in _waves[target]) {
      if (wave.isMouseDown) {
        wave.isMouseDown = false;
        wave.mouseUpWallClock = new DateTime.now().millisecondsSinceEpoch;
        wave.mouseDownMs = wave.mouseUpWallClock - wave.mouseDownWallClock;
        break;
      }
    }
    if (_requestedAnimationFrame == null) {
      _requestedAnimationFrame =
          window.requestAnimationFrame((num frame) => _animate());
    }
  }

  static String _cssColorWithAlpha(String cssColor, [double alpha = 1.0]) {
    var cssColorRegex = new RegExp(r'^rgb\((\d+,\s*\d+,s*\d+)\)$');
    var match = cssColorRegex.firstMatch(cssColor);
    if (match == null) {
      return 'rgba(255, 255, 255, $alpha)';
    }
    return 'rgba(${match.group(1)}, $alpha)';
  }

  void _animate() {
    var wavesToDelete = [];
    var shouldRenderNextFrame = false;
    var longestTouchDownDuration = 0.0;
    var longestTouchUpDuration = 0.0;
    var lastWaveColor = null;

    for (var waveyRow in _waves.keys) {
      for (var wave in _waves[waveyRow]) {
        if (wave.mouseUpWallClock > 0) {
          wave.mouseUpMs =
              new DateTime.now().millisecondsSinceEpoch - wave.mouseUpWallClock;
        } else if (wave.mouseDownWallClock > 0) {
          wave.mouseDownMs = new DateTime.now().millisecondsSinceEpoch -
              wave.mouseDownWallClock;
        }
        longestTouchDownDuration =
            max(longestTouchDownDuration, wave.mouseDownMs);
        longestTouchUpDuration = max(longestTouchUpDuration, wave.mouseUpMs);
        var radius =
            _waveRadiusForTimes(wave.mouseDownMs, wave.mouseUpMs, wave);
        var waveAlpha = _waveOpacityForTimes(wave.mouseUpMs);
        var waveColor = _cssColorWithAlpha(wave.fgColor, waveAlpha);
        lastWaveColor = wave.fgColor;
        var x = wave.startPosition.x;
        var y = wave.startPosition.y;
        if (wave.endPosition != null) {
          var translateFraction =
              min(1, radius / wave.clientSize.toDouble() * 2 / sqrt(2));
          x += translateFraction * (wave.endPosition.x - wave.startPosition.x);
          y += translateFraction * (wave.endPosition.y - wave.startPosition.y);
        }
        var bgFillColor = null;
        var bgFillAlpha = null;
        if (_backgroundFill) {
          bgFillAlpha =
              _waveOuterOpacityForTime(wave.mouseDownMs, wave.mouseUpMs);
          bgFillColor = _cssColorWithAlpha(wave.fgColor, bgFillAlpha);
        }
        _drawRipple(wave, x, y, radius, waveAlpha, bgFillAlpha, wave.fgColor);
        var maximumWave = _waveAtMaximum(wave, radius);
        var waveDissipated = _waveDidFinish(wave, radius);
        var shouldKeepWave = !waveDissipated;
        var shouldRenderWaveAgain =
            (wave.mouseUpMs <= 0) ? !maximumWave : !waveDissipated;
        if (shouldRenderWaveAgain) {
          shouldRenderNextFrame = true;
        }
        if (!shouldKeepWave) {
          wavesToDelete.add(wave);
        }
      }
    }
    if (shouldRenderNextFrame) {
      _requestedAnimationFrame =
          window.requestAnimationFrame((time) => _animate());
    } else {
      _requestedAnimationFrame = null;
    }
    for (var wave in wavesToDelete) {
      _removeFromScope(wave);
    }
    if (_waves.isEmpty) {
      querySelectorAll('.paper-ripple-bg').forEach(
          (DivElement element) => element.style.backgroundColor = null);
      _requestedAnimationFrame = null;
      fire('core-transitionend');
    }
  }

  int _requestedAnimationFrame = null;
  bool _backgroundFill = true;

  void tapProject(Event event) {
    String projectId;
    for (Element row in event.path) {
      if (row.classes.contains('table-body-row')) {
        projectId = row.getAttribute('data-project-id');
        break;
      }
    }
    appPager.openProject(projectId);
    appPager.selected = 1;
  }
}

class Wave {
  final DivElement row;
  int clientWidth;
  int clientHeight;
  int clientSize;

  double maxRadius;
  final String fgColor;

  int mouseDownWallClock = 0;
  int mouseUpWallClock = 0;

  int mouseDownMs = 0;
  int mouseUpMs = 0;
  bool isMouseDown = false;
  Point startPosition;
  Point endPosition;
  double slideDistance = 0.0;

  final List<Element> wave;
  final List<Element> wc;
  final StreamSubscription listener;

  Wave({double this.maxRadius, String this.fgColor, List<Element> this.wave,
      List<Element> this.wc, Point this.startPosition, Point this.endPosition,
      int this.clientSize, int this.clientWidth, int this.clientHeight,
      DivElement this.row, StreamSubscription this.listener});
}
