import 'dart:html';
import 'dart:math';

import 'package:core_elements/core_animated_pages.dart';
import 'package:paper_elements/paper_button.dart';
import 'package:polymer/polymer.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'a_la_carte_page_common.dart';
import 'a_la_carte_main_view.dart';

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

  static const int waveMaxRadius = 500;
  final Set<Wave> waves = new Set<Wave>();

  ALaCarteCardView.created() : super.created();

  @override void domReady() {
    $['loading-cell'].onTransitionEnd.listen((transition) {
      if (projectsAreLoaded) {
        transition.target.classes.add('hidden');
      }
      else {
        transition.target.classes.remove('hidden');
        showSpinner = true;
      }
    });
    $['no-projects-cell'].onTransitionEnd.listen((transition) {
      if (noProjectsFound) {
        transition.target.classes.remove('hidden');
      }
      else {
        transition.target.classes.add('hidden');
      }
    });
  }

  void handleSelect(Event ev) {
    var openCode = (ev.target as PaperButton).getAttribute('data-project-id');
    if (openCode != null) {
      project = projects[openCode];
      (parentNode as CoreAnimatedPages).selected = 'categories';
    }
  }
  void projectsAreLoadedChanged(bool oldValue) {
    Element loadingCell = $['loading-cell'];
    if (projectsAreLoaded) {
      showSpinner = false;
      loadingCell.classes.add('hide');
    } else {
      loadingCell.classes.remove('hide');
    }
  }
  void noProjectsFoundChanged(bool oldValue) {
    Element noProjectsCells = $['no-projects-cell'];
    if (noProjectsFound) {
      noProjectsCells.classes.remove('hide');
    } else {
      noProjectsCells.classes.add('hide');
    }
  }

  @override
  String get backgroundImage => 'https://www.polymer-project.org/components/core-scroll-header-panel/demos/images/bg9.jpg';

  @override
  void fabAction() {
    assert(pageList is ALaCarteMainView);
    pageList.selected = 1;
    pageList.project = new Project('foo-bar');

  }

  @override
  String get fabIcon => 'add';

  double waveRadiusOfT(int touchDownMs, int touchUpMs, RippleAnimation anim) {
    var touchDown = touchDownMs.toDouble() / 1000;
    var touchUp = touchUpMs.toDouble() / 1000;
    var elapsed = touchDown + touchUp;
    var ww = anim.width.toDouble();
    var hh = anim.height.toDouble();
    var waveRadius = min(sqrt(hh*hh + ww*ww), waveMaxRadius) * 1.1 + 5;
    var duration = 1.1 - 0.2*waveRadius / waveMaxRadius;
    var tt = elapsed / duration;
    var size = waveRadius * (1 - pow(80, -tt));
    return size.abs();
  }
  double waveOpacityOfT(int touchDownMs, int touchUpMs, RippleAnimation anim) {
    var touchUp = touchUpMs.toDouble() / 1000;
    if (touchUp <= 0) {
      return anim.initialOpacity;
    }
    return max(0.0, anim.initialOpacity - touchUp*anim.opacityDecayVelocity);
  }
  double outerOpacityOfT(int touchDownMs, int touchUpMs, RippleAnimation anim) {
    var touchDown = touchDownMs.toDouble() / 1000;
    var outerOpacity = touchDown*0.3;
    var waveOpacity = waveOpacityOfT(touchDownMs, touchUpMs, anim);
    return max(0.0, min(outerOpacity, waveOpacity));
  }
  bool waveDidFinish(Wave wave, double radius, RippleAnimation anim) {
    var waveOpacity = waveOpacityOfT(wave.touchDownMs, wave.touchUpMs, anim);
    return waveOpacity < 0.01 && radius >= min(wave.maxRadius, waveMaxRadius);
  }
  bool waveIsAtMaximum(Wave wave, double radius, RippleAnimation anim) {
    var waveOpacity = waveOpacityOfT(wave.touchDownMs, wave.touchUpMs, anim);
    return waveOpacity >= anim.initialOpacity && radius >= min(wave.maxRadius, waveMaxRadius);
  }
  void drawRipple(DivElement context, double x, double y, double radius, double innerAlpha, double outerAlpha) {
    context.querySelectorAll('.ripple-bg').forEach((Element e) {
      if (outerAlpha != null)
        e.style.opacity = outerAlpha.toString();
    });
    var containerSize = max(context.offset.height, context.offset.width);

    var s = 2 * radius / containerSize.toDouble();
    var dx = x - (context.offset.width.toDouble() / 2);
    var dy = y - (context.offset.height.toDouble() / 2);

    context.querySelectorAll('.ripple-wave').forEach((Element e) {
      e.style.opacity = innerAlpha.toString();
      e.style.transform = 'scale3d($s, $s, 1)';
    });
    context.querySelectorAll('.ripple-wc').forEach((Element e) {
      e.style.transform = 'translate3d(${dx}px, ${dy}px, 0)';
    });
  }
  Wave createWave(DivElement context) {
    var elementStyle = context.getComputedStyle();
    var fgColor = elementStyle.color;
    context.querySelectorAll('.ripple-bg').forEach((Element e) {
      e.style.backgroundColor = fgColor;
    });
    context.querySelectorAll('.ripple-wave').forEach((Element e) {
      var inner = document.createElement('div');
      inner.style.backgroundColor = fgColor;
      inner.classes.add('wave');
      var outer = document.createElement('div');
      outer.classes.add('wave-container');
      outer.append(inner);
      e.append(outer);
    });
    return new Wave(
        context: context,
        waveColor: fgColor,
        touchDownMs: 0,
        touchUpMs: 0,
        maxRadius: 0.0,
        isMouseDown: false,
        mouseDownStart: 0.0,
        mouseUpStart: 0.0
    );
  }
  void removeWave(Wave wave) {
    if (waves.contains(wave)) {
      waves.remove(wave);
      wave.context.querySelectorAll('.ripple-wc').forEach((Element e) => e.remove());
    }
  }
}

class RippleAnimation extends Object {
  final double initialOpacity;
  final double opacityDecayVelocity;
  final int height;
  final int width;

  RippleAnimation(this.initialOpacity, this.opacityDecayVelocity, this.height, this.width);
}

class Wave extends Object {
  int touchDownMs;
  int touchUpMs;
  double mouseDownStart;
  double mouseUpStart;
  double maxRadius;
  bool isMouseDown;
  final String waveColor;
  final DivElement context;
  Wave({
      this.context, this.waveColor, this.touchDownMs, this.touchUpMs,
      this.maxRadius, this.isMouseDown, this.mouseDownStart, this.mouseUpStart
  });
}



/*
(function() {
  // Shortcuts.
  var pow = Math.pow;
  var now = Date.now;
  if (window.performance && performance.now) {
    now = performance.now.bind(performance);
  }

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

function dist(p1, p2) {
  return Math.sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
}

function distanceFromPointToFurthestCorner(point, size) {
  var tl_d = dist(point, {x: 0, y: 0});
  var tr_d = dist(point, {x: size.w, y: 0});
  var bl_d = dist(point, {x: 0, y: size.h});
  var br_d = dist(point, {x: size.w, y: size.h});
  return Math.max(tl_d, tr_d, bl_d, br_d);
}

Polymer('paper-ripple', {

/**
 * The initial opacity set on the wave.
 *
 * @attribute initialOpacity
 * @type number
 * @default 0.25
 */
initialOpacity: 0.25,

/**
 * How fast (opacity per second) the wave fades out.
 *
 * @attribute opacityDecayVelocity
 * @type number
 * @default 0.8
 */
opacityDecayVelocity: 0.8,

backgroundFill: true,
pixelDensity: 2,

eventDelegates: {
down: 'downAction',
up: 'upAction'
},

ready: function() {
this.waves = [];
},

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
wave.isMouseDown = false
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

*/
