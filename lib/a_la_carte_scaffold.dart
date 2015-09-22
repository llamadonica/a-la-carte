library a_la_carte.client.a_la_carte_scaffold;

import 'dart:async';
import 'dart:html';
import 'dart:js';
import 'dart:math';

import 'package:core_elements/core_drawer_panel.dart';
import 'package:core_elements/core_icon_button.dart';
import 'package:core_elements/core_scroll_header_panel.dart';
import 'package:polymer/polymer.dart';

@CustomTag('a-la-carte-scaffold')
class ALaCarteScaffold extends PolymerElement {
  static const EventStreamProvider<CustomEvent> dgsFabActionEvent =
      const EventStreamProvider<CustomEvent>('dgs-fab-action');
  @observable String paperFabInternal;
  @observable bool docked;
  @observable bool fabShowing = true;
  @published String responsiveWidth;
  @published String fabIcon;
  @PublishedProperty(reflect: true) bool narrow;
  @published String titleOverride;
  @published String backgroundImage;
  @PublishedProperty(reflect: true) String mode = 'seamed';
  @published int headerHeight = 192;
  @published int condensedHeaderHeight = 64;
  int _scrollFrame = null;
  int trackStart;
  int track;
  bool _isInDock = false;

  ALaCarteScaffold.created() : super.created();

  CoreDrawerPanel get drawerPanel => $['drawer-panel'];
  Element get headerBg => $['header-bg'];
  CoreIconButton get menuButton => $['menu-button'];
  Element get scrollThumb => $['scroll-thumb'];
  Element get scrollTrack => $['scroll-track'];
  Element get scroller => $['main-container'];
  Element get toolbarTitle => $['toolbar-title'];
  Element get headerContainer => $['header-container'];
  Stream<CustomEvent> get onDgsFabAction => dgsFabActionEvent.forElement(this);

  void backgroundImageChanged(String oldValue) {
    headerBg.style.backgroundImage = backgroundImage == null
        ? null
        : backgroundImage == '' ? '' : "url('$backgroundImage')";
  }

  void closeDrawer() {
    drawerPanel.closeDrawer();
    transitonMenuButtonToMenu();
  }

  void doMainFabAction(ev) {
    fire('dgs-fab-action');
  }

  void dockedChanged(bool oldValue) {
    if ((docked != null) && docked && (oldValue != null) && !oldValue) {
      shadowRoot.querySelectorAll('paper-fab').forEach((Element e) {
        e.style
          ..position = null
          ..top = null;
      });
    }
  }

  void fabIconChanged(String oldValue) {
    if (fabIcon != null) {
      paperFabInternal = fabIcon;
      fabShowing = true;
    } else {
      fabShowing = false;
    }
  }

  void headerTransform(CustomEvent e) {
    final CoreScrollHeaderPanel headerPanel = e.currentTarget;
    var offset = headerPanel.querySelector('#main-container').scrollTop;
    if (headerPanel.condensedHeaderHeight == null ||
        headerPanel.headerHeight == null) return;
    var height = max(
        headerPanel.condensedHeaderHeight, headerPanel.headerHeight - offset);
    headerPanel.querySelector('#header-container').style.height = '${height}px';
  }

  void dockHeader() {
    _isInDock = true;

    headerContainer.attributes['docked'] = '';
    scroller.attributes['docked'] = '';
    var bgContainerRipple = $['bg-container-ripple'];
    var width = bgContainerRipple.offsetWidth;
    var height = bgContainerRipple.offsetHeight;
    //    function waveRadiusFn(touchDownMs, touchUpMs, anim) {
    //  // Convert from ms to s
    //  var touchDown = touchDownMs / 1000;
    //  var touchUp = touchUpMs / 1000;
    //  var totalElapsed = touchDown + touchUp;
    //  var ww = anim.width, hh = anim.height;
    //  // use diagonal size of container to avoid floating point math sadness
    //  var waveRadius = Math.min(Math.sqrt(ww * ww + hh * hh), waveMaxRadius) * 1.1 + 5;
    //  var duration = 1.1 - .2 * (waveRadius / waveMaxRadius);
    //  var tt = (totalElapsed / duration);

    //  var size = waveRadius * (1 - Math.pow(80, -tt));
    //  return Math.abs(size);
    //}
    // dSize = waveRadius *
    // dtt = dElapsed / duration
    //
    var waveMaxRadius =
        min(sqrt((width * width + height * height).toDouble()), 150.0);
    var waveFRadius = waveMaxRadius * 1.1 + 5.0;
    var duration = 1.1 - .2 * (waveFRadius / waveMaxRadius);
    var sizeFactorAtMax = 1 - waveMaxRadius / waveFRadius;
    var tFactor = -log(sizeFactorAtMax) / log(80);
    var durationAtMax = tFactor * duration;

    bgContainerRipple.jsElement.callMethod('downAction', [
      new JsObject.jsify({'x': width - 116, 'y': 28})
    ]);
    new Timer(new Duration(milliseconds: (durationAtMax * 1000).floor()), () {
      bgContainerRipple.jsElement.callMethod('upAction', [
        new JsObject.jsify({'x': width - 116, 'y': 28})
      ]);
    });
    var greaterRadius = sqrt(((height - 28) * (height - 28) +
        (width - 116) * (width - 116)).toDouble());
    var durationOfSubRipple = greaterRadius / waveFRadius * duration / log(80);

    var baseWidth = greaterRadius * 2;
    var baseHeight = greaterRadius * 2;
    var baseLeft = width - 116 - greaterRadius;
    var baseTop = 28 - greaterRadius;
    DivElement extraRippleContainer = $['extra-ripple-container'];
    var subRipple = new DivElement()
      ..classes.add('color-change-ripple')
      ..classes.add('start')
      ..style.transition = 'opacity ${durationOfSubRipple}s linear,'
          ' transform ${durationOfSubRipple}s linear'
      ..style.width = '${baseWidth}px'
      ..style.height = '${baseHeight}px'
      ..style.left = '${baseLeft}px'
      ..style.top = '${baseTop}px';
    extraRippleContainer.append(subRipple);
    window.animationFrame.then((_) => subRipple..classes.remove('start'));
    subRipple.onTransitionEnd.first
        .then((_) => _subRippleTransitionEnd(subRipple, _));
  }

  void _subRippleTransitionEnd(DivElement subRipple, Event _) {
    subRipple.remove();
    if (_isInDock) {
      $['condensed-header-bg'].classes.add('utility');
      $['toolbar-title'].classes..add('concealed')..add('hidden');
    } else {
      $['condensed-header-bg'].classes.remove('utility');
      $['toolbar-title'].classes.remove('concealed');
    }
  }

  void undockHeader() {
    _isInDock = false;
    headerContainer.attributes.remove('docked');
    scroller.classes.add('undocking');
    scroller.attributes.remove('docked');
    scroller.onTransitionEnd.first.then((_) {
      scroller.classes.remove('undocking');
    });
    var bgContainerRipple = $['bg-container-ripple'];
    var width = bgContainerRipple.offsetWidth;
    var height = bgContainerRipple.offsetHeight;
    //    function waveRadiusFn(touchDownMs, touchUpMs, anim) {
    //  // Convert from ms to s
    //  var touchDown = touchDownMs / 1000;
    //  var touchUp = touchUpMs / 1000;
    //  var totalElapsed = touchDown + touchUp;
    //  var ww = anim.width, hh = anim.height;
    //  // use diagonal size of container to avoid floating point math sadness
    //  var waveRadius = Math.min(Math.sqrt(ww * ww + hh * hh), waveMaxRadius) * 1.1 + 5;
    //  var duration = 1.1 - .2 * (waveRadius / waveMaxRadius);
    //  var tt = (totalElapsed / duration);

    //  var size = waveRadius * (1 - Math.pow(80, -tt));
    //  return Math.abs(size);
    //}
    // dSize = waveRadius *
    // dtt = dElapsed / duration
    //
    var waveMaxRadius =
        min(sqrt((width * width + height * height).toDouble()), 150.0);
    var waveFRadius = waveMaxRadius * 1.1 + 5.0;
    var duration = 1.1 - .2 * (waveFRadius / waveMaxRadius);
    var sizeFactorAtMax = 1 - waveMaxRadius / waveFRadius;
    var tFactor = -log(sizeFactorAtMax) / log(80);
    var durationAtMax = tFactor * duration;

    var greaterRadius = sqrt(((height - 28) * (height - 28) +
        (width - 116) * (width - 116)).toDouble());
    var durationOfSubRipple = greaterRadius / waveFRadius * duration / log(80);
    durationOfSubRipple = max(durationOfSubRipple, 0.7);

    var baseWidth = greaterRadius * 2;
    var baseHeight = greaterRadius * 2;
    var baseLeft = width - 116 - greaterRadius;
    var baseTop = 28 - greaterRadius;
    DivElement extraRippleContainer = $['extra-ripple-container'];
    var subRipple = new DivElement()
      ..classes.add('color-change-ripple')
      ..classes.add('start')
      ..style.transition = 'opacity ${durationOfSubRipple}s linear,'
          ' transform ${durationOfSubRipple}s linear'
      ..style.width = '${baseWidth}px'
      ..style.height = '${baseHeight}px'
      ..style.left = '${baseLeft}px'
      ..style.backgroundColor = '#5677fc'
      ..style.top = '${baseTop}px';
    extraRippleContainer.append(subRipple);
    window.animationFrame.then((_) => subRipple..classes.remove('start'));
    $['toolbar-title'].classes.remove('hidden');
    subRipple.onTransitionEnd.first.then((_) {
      _subRippleTransitionEnd(subRipple, _);
    });
  }

  void narrowChanged(bool oldValue) {
    if (narrow != null && !narrow) {
      shadowRoot.querySelector('#drawer-panel /deep/ #drawer')
        ..style.transition = null;
      menuButton.icon = 'menu-animation:menu-transition-to-arrow';
      menuButton.attributes..remove('arrow')..remove('animate');
    } else {
      shadowRoot.querySelector('#drawer-panel /deep/ #drawer')
        ..style.transition =
            'transform ease-in-out 0.3s, width ease-in-out 0.3s, top 0s linear 0.3s'
        ..onTransitionEnd.listen((TransitionEvent ev) {
          if (ev.propertyName == 'top') (ev.target as Element)
              .style
              .transition = null;
        });
    }
  }

  void openDrawer() {
    drawerPanel.openDrawer();
    transitionMenuButtonToArrow();
  }

  @override void ready() {
    scroller.onScroll.listen(scroll);
    window.onResize.listen(scroll);
    drawerPanel.shadowRoot.querySelector('#scrim').addEventListener('tap',
        (ev) {
      toggleMenuButton();
    });
    scroll(null);
  }

  void scroll(_) {
    if (_scrollFrame == null) {
      _scrollFrame = window.requestAnimationFrame((time) {
        var offsetY = max(scroller.scrollTop, 0);

        var windowHeight = scroller.offsetHeight;
        var containerHeight = scroller.scrollHeight;

        var height = max(condensedHeaderHeight, headerHeight - offsetY);
        var delta = (height - condensedHeaderHeight).toDouble() /
            (headerHeight - condensedHeaderHeight).toDouble();
        docked = (delta != 0.0);
        if (!docked) {
          shadowRoot.querySelectorAll('paper-fab').forEach((Element e) {
            e.style
              ..position = 'fixed'
              ..top = '${64-29}px';
          });
        }
        headerBg.style.opacity = delta.toString();
        if (toolbarTitle != null) {
          toolbarTitle.style.transform = 'scale(${delta*0.4 + 0.6})';
        }
        scroller.style.top =
        headerContainer.style.height = '${height}px';

        if (containerHeight <= windowHeight) {
          scrollTrack.attributes['disabled'] = '';
        } else {
          scrollTrack.attributes.remove('disabled');

          var scrollbarHeight = scrollTrack.offsetHeight;

          var percentWindow =
              windowHeight.toDouble() / containerHeight.toDouble();
          var windowPosition = offsetY.toDouble() /
              (containerHeight.toDouble() - windowHeight.toDouble());

          windowPosition = max(0, min(1, windowPosition));

          var scrollThumbHeight = min(
              scrollbarHeight,
              max(
                  6,
                  max(scrollbarHeight / 3,
                      max(20, scrollbarHeight * percentWindow)))).round();
          var scrollbarTop =
              (windowPosition * (scrollbarHeight - scrollThumbHeight)).round();
          scrollThumb.style
            ..height = '${scrollThumbHeight}px'
            ..top = '${scrollbarTop}px';
        }
        _scrollFrame = null;
      });
    }
  }

  void toggleMenuButton() {
    if (drawerPanel.selected != "drawer") {
      transitonMenuButtonToMenu();
    } else {
      transitionMenuButtonToArrow();
    }
  }

  void togglePanel() {
    drawerPanel.togglePanel();
    toggleMenuButton();
  }

  void trackEndScrollerThumb(ev) {
    scrollThumb.attributes.remove('dragging');
  }

  void trackScrollerThumb(ev) {
    var event = new JsObject.fromBrowserObject(ev);
    var dx = event['clientY'] - trackStart;
    Element thumb = scrollThumb;

    var percentageFromTop = (dx + track).toDouble() /
        (thumb.parent.clientHeight - thumb.offsetHeight).toDouble();
    percentageFromTop = min(1, max(0, percentageFromTop));

    var newTop =
        min(thumb.parent.offsetHeight - thumb.clientHeight, max(0, track + dx));
    thumb.style.top = '${newTop}px';

    var windowHeight = scroller.offsetHeight;
    var containerHeight = scroller.scrollHeight;
    scroller.scrollTop = ((containerHeight - windowHeight).toDouble() *
        percentageFromTop).floor();
    scroll(null);
  }

  void trackStartScrollerThumb(ev) {
    var event = new JsObject.fromBrowserObject(ev);
    trackStart = event['clientY'];
    Element thumb = scrollThumb;
    track = thumb.offsetTop;
    thumb.attributes['dragging'] = '';
  }

  void transitionMenuButtonToArrow() {
    menuButton.attributes
      ..putIfAbsent('animate', () => '')
      ..putIfAbsent('arrow', () => '');
    menuButton.shadowRoot
        .querySelector('#top-bar')
        .onTransitionEnd
        .first
        .then((_) {
      if (drawerPanel.selected == "drawer") menuButton.icon = 'arrow-back';
      menuButton.attributes.remove('animate');
    });
  }

  void transitonMenuButtonToMenu() {
    menuButton.attributes
      ..putIfAbsent('animate', () => '')
      ..putIfAbsent('arrow', () => '');
    menuButton.icon = 'menu-animation:menu-transition-to-arrow';
    new Future(() {
      menuButton.attributes.remove('arrow');
      return menuButton.shadowRoot
          .querySelector('#top-bar')
          .onTransitionEnd
          .first;
    }).then((_) {
      if (drawerPanel.selected == "drawer") menuButton.icon = 'arrow-back';
      menuButton.attributes.remove('animate');
    });
  }
}
