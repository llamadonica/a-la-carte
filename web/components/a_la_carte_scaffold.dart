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
  int scrollFrame = null;
  int trackStart;
  int track;
  
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
    headerBg.style.backgroundImage =
        backgroundImage == '' ? '' : "url('$backgroundImage')";
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
    paperFabInternal = fabIcon;
  }

  void headerTransform(CustomEvent e) {
    final CoreScrollHeaderPanel headerPanel = e.currentTarget;
    var offset = headerPanel.querySelector('#main-container').scrollTop;
    if (headerPanel.condensedHeaderHeight == null ||
        headerPanel.headerHeight == null) return;
    var height =
        max(headerPanel.condensedHeaderHeight, headerPanel.headerHeight - offset);
    headerPanel.querySelector('#header-container').style.height = '${height}px';
  }

  void narrowChanged(bool oldValue) {
    if (narrow != null && !narrow) {
      shadowRoot.querySelector('#drawer-panel /deep/ #drawer')..style.transition =
          null;
      menuButton.icon = 'menu-animation:menu-transition-to-arrow';
      menuButton.attributes
          ..remove('arrow')
          ..remove('animate');
    } else {
      shadowRoot.querySelector('#drawer-panel /deep/ #drawer')
          ..style.transition =
              'transform ease-in-out 0.3s, width ease-in-out 0.3s, top 0s linear 0.3s'
          ..onTransitionEnd.listen((TransitionEvent ev) {
            if (ev.propertyName == 'top') (ev.target as Element).style.transition =
                null;
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
    drawerPanel.shadowRoot.querySelector(
        '#scrim').addEventListener('tap', (ev) {
      toggleMenuButton();
    });
    scroll(null);
  }

  void scroll(Event e) {
    if (scrollFrame == null) {
      scrollFrame = window.requestAnimationFrame((time) {
        var offsetY = max(scroller.scrollTop, 0);

        var windowHeight = scroller.offsetHeight;
        var containerHeight = scroller.scrollHeight;

        var height = max(condensedHeaderHeight, headerHeight - offsetY);
        var delta =
            (height - condensedHeaderHeight).toDouble() /
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
        //mainContainer.style.top =
        headerContainer.style.height = '${height}px';
        if (containerHeight <= windowHeight) {
          scrollTrack.attributes['disabled'] = '';
        } else {
          scrollTrack.attributes.remove('disabled');

          var scrollbarHeight = scrollTrack.offsetHeight;

          var percentWindow =
              windowHeight.toDouble() /
              containerHeight.toDouble();
          var windowPosition =
              offsetY.toDouble() /
              (containerHeight.toDouble() - windowHeight.toDouble());

          windowPosition = max(0, min(1, windowPosition));

          var scrollThumbHeight = min(
              scrollbarHeight,
              max(
                  6,
                  max(scrollbarHeight / 3, max(20, scrollbarHeight * percentWindow)))).round();
          var scrollbarTop =
              (windowPosition * (scrollbarHeight - scrollThumbHeight)).round();
          scrollThumb.style
              ..height = '${scrollThumbHeight}px'
              ..top = '${scrollbarTop}px';
        }

        new Future(() {
          scrollFrame = null;
        });
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

    var percentageFromTop =
        (dx + track).toDouble() /
        (thumb.parent.clientHeight - thumb.offsetHeight).toDouble();
    percentageFromTop = min(1, max(0, percentageFromTop));

    var newTop =
        min(thumb.parent.offsetHeight - thumb.clientHeight, max(0, track + dx));
    thumb.style.top = '${newTop}px';

    var windowHeight = scroller.offsetHeight;
    var containerHeight = scroller.scrollHeight;
    scroller.scrollTop =
        ((containerHeight - windowHeight).toDouble() * percentageFromTop).floor();
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
    menuButton.shadowRoot.querySelector(
        '#top-bar').onTransitionEnd.first.then((_) {
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
      return menuButton.shadowRoot.querySelector(
          '#top-bar').onTransitionEnd.first;
    }).then((_) {
      if (drawerPanel.selected == "drawer") menuButton.icon = 'arrow-back';
      menuButton.attributes.remove('animate');
    });
  }
}
