import 'dart:html';
import 'dart:math';

import 'package:core_elements/core_animated_pages.dart';
import 'package:paper_elements/paper_button.dart';
import 'package:polymer/polymer.dart';
import 'package:uuid/uuid.dart';

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

  Set<Wave> _waves = new Set<Wave>();

  ALaCarteCardView.created() : super.created();

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
    appPager.selected = 1;
  }

  @override
  String get fabIcon => 'add';

  static const double _waveMaxRadius = 150.0;
  static const double _waveInitialOpacity = 0.25;
  static const double _waveOpacityDecayVelocity = 0.8;

  static double _waveRadiusForTimes(
      int touchDownMs, int touchUpMs, Wave animContainer) {
    var touchDown = touchDownMs.toDouble() / 1000;
    var touchUp = touchUpMs.toDouble() / 1000;
    var totalElapsed = touchDown + touchUp;
    var width = animContainer.clientWidth.toDouble();
    var height = animContainer.clientHeight.toDouble();
    var waveRadius =
        min(sqrt(width * width + height * height), _waveMaxRadius) * 1.1 + 5.0;
    var duration = 1.1 - 0.2 * (waveRadius / _waveMaxRadius);
    var timePortion = totalElapsed / duration;
    var size = waveRadius * (1 - pow(80, -timePortion));
    return size.abs();
  }

  static double _waveOpacityForTimes(int touchUpMs) {
    var touchUp = touchUpMs.toDouble() / 1000;
    if (touchUpMs <= 0) {
      return _waveInitialOpacity;
    }
    return max(0, _waveInitialOpacity - touchUp * _waveOpacityDecayVelocity);
  }

  static double _waveOuterOpacityForTime(int touchDownMs, int touchUpMs) {
    var touchDown = touchDownMs.toDouble() / 1000;
    var outerOpacity = touchDown * 0.3;
    var waveOpacity = _waveOpacityForTimes(touchUpMs);
    return max(0, min(outerOpacity, waveOpacity));
  }

  static bool _waveDidFinish(Wave wave, double radius) =>
      _waveOpacityForTimes(wave.touchUpMs) < 0.01 &&
          radius > min(wave.maxRadius, _waveMaxRadius);

  static bool _waveAtMaximum(Wave wave, double radius) =>
      _waveOpacityForTimes(wave.touchUpMs) > _waveInitialOpacity &&
          radius >= min(wave.maxRadius, _waveMaxRadius);

  static void _drawRipple(Wave context, int x, int y, double radius,
      double innerAlpha, double outerAlpha) {
    context.row.querySelectorAll('.paper-ripple-bg').forEach(
        (DivElement element) => element.style.opacity = outerAlpha.toString());
    var s = radius / (context.clientSize / 2);
    var dx = x - (context.clientWidth / 2);
    var dy = y - (context.clientHeight / 2);
    context.row
        .querySelectorAll('.paper-ripple-wave')
        .forEach((DivElement element) {
      element.style.opacity = innerAlpha.toString();
      element.style.transform = 'scale3d($s, $s, 1)';
    });
    context.row
        .querySelectorAll('.paper-ripple-wc')
        .forEach((DivElement element) {
      element.style.transform = 'translate3d(${dx}px, ${dy}px, 0)';
    });
  }

  static Wave _createWave(DivElement row) {
    var fgColor = row.getComputedStyle().color;
    var wave = new List<Element>();
    var wc = new List<Element>();
    row.querySelectorAll('.paper-ripple-bg').forEach((DivElement element) =>
        element.style.backgroundColor = fgColor.toString());
    row.querySelectorAll('.table-body-cell').forEach((DivElement element) {
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
    });
    return new Wave(
        touchUpMs: 0,
        maxRadius: 0.0,
        fgColor: fgColor,
        wave: wave,
        wc: wc,
        row: row);
  }

  void _removeFromScope(Wave wave) {
    if (_waves.contains(wave)) {
      wave.wc.forEach((Element el) => el.remove());
      _waves.remove(wave);
    }
  }

  void onDownOverEntry(MouseEvent event) {
    Element target = event.target;
    var wave = _createWave(target);
    wave.mouseDownWallClock = new DateTime.now().millisecondsSinceEpoch;
    wave.isMouseDown = true;
    var rectangle = target.client;
    var width = rectangle.width;
    var height = rectangle.height;
    var x = event.client.x - rectangle.left;
    var y = event.client.y - rectangle.top;
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
  }
}

class Wave {
  final DivElement row;
  int clientWidth;
  int clientHeight;
  int clientSize;

  int touchUpMs;
  final double maxRadius;
  final String fgColor;

  int mouseDownWallClock = 0;

  int mouseDownMs = 0;
  int mouseUpMs = 0;
  bool isMouseDown = false;
  Point startPosition;
  Point endPosition;
  double slideDistance = 0.0;

  final List<Element> wave;
  final List<Element> wc;

  Wave({int this.touchUpMs, double this.maxRadius, String this.fgColor,
      List<Element> this.wave, List<Element> this.wc, Point this.startPosition,
      Point this.endPosition, int this.clientSize, int this.clientWidth,
      int this.clientHeight, DivElement this.row});
}

/*
 *   (function() {
    //
    // SETUP
    //
    function cssColorWithAlpha(cssColor, alpha) {
        var parts = cssColor.match(/^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/);
        if (typeof alpha == 'undefined') {
            alpha = 1;
        }
        if (!parts) {
          return 'rgba(255, 255, 255, ' + alpha + ')';
        }
        return 'rgba(' + parts[1] + ', ' + parts[2] + ', ' + parts[3] + ', ' + alpha + ')';
    }
    function distanceFromPointToFurthestCorner(point, size) {
      var tl_d = dist(point, {x: 0, y: 0});
      var tr_d = dist(point, {x: size.w, y: 0});
      var bl_d = dist(point, {x: 0, y: size.h});
      var br_d = dist(point, {x: size.w, y: size.h});
      return Math.max(tl_d, tr_d, bl_d, br_d);
    }
    Polymer('paper-ripple', {
      downAction: function(e) {
        var wave = createWave(this);
        this.cancelled = false;
        wave.isMouseDown = true;
        wave.tDown = 0.0;
        wave.tUp = 0.0;
        wave.mouseUpStart = 0.0;
        wave.mouseDownStart = now();
        var rect = this.getBoundingClientRect();
        var width = rect.width;
        var height = rect.height;
        var touchX = e.x - rect.left;
        var touchY = e.y - rect.top;
        wave.startPosition = {x:touchX, y:touchY};
        if (this.classList.contains("recenteringTouch")) {
          wave.endPosition = {x: width / 2,  y: height / 2};
          wave.slideDistance = dist(wave.startPosition, wave.endPosition);
        }
        wave.containerSize = Math.max(width, height);
        wave.containerWidth = width;
        wave.containerHeight = height;
        wave.maxRadius = distanceFromPointToFurthestCorner(wave.startPosition, {w: width, h: height});
        // The wave is circular so constrain its container to 1:1
        wave.wc.style.top = (wave.containerHeight - wave.containerSize) / 2 + 'px';
        wave.wc.style.left = (wave.containerWidth - wave.containerSize) / 2 + 'px';
        wave.wc.style.width = wave.containerSize + 'px';
        wave.wc.style.height = wave.containerSize + 'px';
        this.waves.push(wave);
        if (!this._loop) {
          this._loop = this.animate.bind(this, {
            width: width,
            height: height
          });
          requestAnimationFrame(this._loop);
        }
        // else there is already a rAF
      },
      upAction: function() {
        for (var i = 0; i < this.waves.length; i++) {
          // Declare the next wave that has mouse down to be mouse'ed up.
          var wave = this.waves[i];
          if (wave.isMouseDown) {
            wave.isMouseDown = false;
            wave.mouseUpStart = now();
            wave.mouseDownStart = 0;
            wave.tUp = 0.0;
            break;
          }
        }
        this._loop && requestAnimationFrame(this._loop);
      },
      cancel: function() {
        this.cancelled = true;
      },
      animate: function(ctx) {
        var shouldRenderNextFrame = false;
        var deleteTheseWaves = [];
        // The oldest wave's touch down duration
        var longestTouchDownDuration = 0;
        var longestTouchUpDuration = 0;
        // Save the last known wave color
        var lastWaveColor = null;
        // wave animation values
        var anim = {
          initialOpacity: this.initialOpacity,
          opacityDecayVelocity: this.opacityDecayVelocity,
          height: ctx.height,
          width: ctx.width
        }
        for (var i = 0; i < this.waves.length; i++) {
          var wave = this.waves[i];
          if (wave.mouseDownStart > 0) {
            wave.tDown = now() - wave.mouseDownStart;
          }
          if (wave.mouseUpStart > 0) {
            wave.tUp = now() - wave.mouseUpStart;
          }
          // Determine how long the touch has been up or down.
          var tUp = wave.tUp;
          var tDown = wave.tDown;
          longestTouchDownDuration = Math.max(longestTouchDownDuration, tDown);
          longestTouchUpDuration = Math.max(longestTouchUpDuration, tUp);
          // Obtain the instantenous size and alpha of the ripple.
          var radius = waveRadiusFn(tDown, tUp, anim);
          var waveAlpha =  waveOpacityFn(tDown, tUp, anim);
          var waveColor = cssColorWithAlpha(wave.waveColor, waveAlpha);
          lastWaveColor = wave.waveColor;
          // Position of the ripple.
          var x = wave.startPosition.x;
          var y = wave.startPosition.y;
          // Ripple gravitational pull to the center of the canvas.
          if (wave.endPosition) {
            // This translates from the origin to the center of the view  based on the max dimension of
            var translateFraction = Math.min(1, radius / wave.containerSize * 2 / Math.sqrt(2) );
            x += translateFraction * (wave.endPosition.x - wave.startPosition.x);
            y += translateFraction * (wave.endPosition.y - wave.startPosition.y);
          }
          // If we do a background fill fade too, work out the correct color.
          var bgFillColor = null;
          if (this.backgroundFill) {
            var bgFillAlpha = waveOuterOpacityFn(tDown, tUp, anim);
            bgFillColor = cssColorWithAlpha(wave.waveColor, bgFillAlpha);
          }
          // Draw the ripple.
          drawRipple(wave, x, y, radius, waveAlpha, bgFillAlpha);
          // Determine whether there is any more rendering to be done.
          var maximumWave = waveAtMaximum(wave, radius, anim);
          var waveDissipated = waveDidFinish(wave, radius, anim);
          var shouldKeepWave = !waveDissipated || maximumWave;
          // keep rendering dissipating wave when at maximum radius on upAction
          var shouldRenderWaveAgain = wave.mouseUpStart ? !waveDissipated : !maximumWave;
          shouldRenderNextFrame = shouldRenderNextFrame || shouldRenderWaveAgain;
          if (!shouldKeepWave || this.cancelled) {
            deleteTheseWaves.push(wave);
          }
       }
        if (shouldRenderNextFrame) {
          requestAnimationFrame(this._loop);
        }
        for (var i = 0; i < deleteTheseWaves.length; ++i) {
          var wave = deleteTheseWaves[i];
          removeWaveFromScope(this, wave);
        }
        if (!this.waves.length && this._loop) {
          // clear the background color
          this.$.bg.style.backgroundColor = null;
          this._loop = null;
          this.fire('core-transitionend');
        }
      }
    });
  })();
 **/
