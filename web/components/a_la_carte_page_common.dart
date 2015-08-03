import 'dart:async';
import 'dart:html';
import 'dart:math' as Math;
import 'dart:js';

import 'package:polymer/polymer.dart';
import 'package:paper_elements/paper_tabs.dart';

abstract class ALaCartePageCommon extends PolymerElement {
  static const TRANSITION_DURATION = const Duration(milliseconds: 500);
  Timer transitionTimer = null;
  @published int selected = 0;

  selectedChanged(int oldValue) {
    shadowRoot.querySelector('core-pages').classes.add('animate');
  }
  ALaCartePageCommon.created() : super.created();
  
  String get fabIcon;
  String get backgroundImage;
  void fabAction();

  int trackStart;
  int track;
  double trackSpeed;
  double lastTimestamp;
  
  static const double MIN_SCALE = 0.9;
  static const double FLING_FACTOR = 10.0;
  static const double NOMINAL_SWITCH_DURATION = 0.2;

  void pageTransitionEnd(Event ev) {
    (ev.target as Element).style.transition = null;
    var corePageClasses = shadowRoot.querySelector('core-pages').classes;
    if (corePageClasses.contains('dragging')) return;
    corePageClasses.remove('animate');
  }

  void trackStartPage(ev) {
    var event = new JsObject.fromBrowserObject(ev);

    shadowRoot.querySelector('core-pages').classes
        ..add('dragging')
        ..add('animate');

    trackStart = event['clientX'];
    track = 0;
    lastTimestamp = event['timeStamp'];
  }
  void trackPage(ev) {
    var event = new JsObject.fromBrowserObject(ev);
    track = Math.min(
        400,
        Math.max(-400, event['clientX'] - trackStart)); //Right is + Left is -

    var opacity = 1 - track.abs().toDouble() / 400;
    var scale = opacity * (1 - MIN_SCALE) + (MIN_SCALE);

    var next = (event['target'] as Node).nextNode;
    for ( ; next != null && next.nodeName != 'SECTION'; next = next.nextNode);
    if (next != null) next.childNodes.forEach(( div) {
      if (div is! DivElement) return;
      if (track < 0) {
        div.style.transform =
            'translateX(${400 + track}px) scale(${(1 + MIN_SCALE) - scale})';
        div.style.opacity = '${1 - opacity}';
      } else {
        div.style.transform = null;
        div.style.opacity = null;
      }
    });
    

    var prev = (event['target'] as Node).previousNode;
    for ( ; prev != null &&
        prev.nodeName != 'SECTION'; prev = prev.previousNode);
    if (prev != null) prev.childNodes.forEach((div) {
      if (div is! DivElement) return;
      if (track > 0) {
        div.style.transform =
            'translateX(${track - 400}px) scale(${(1 + MIN_SCALE) - scale})';
        div.style.opacity = '${1 - opacity}';
      } else {
        div.style.transform = null;
        div.style.opacity = null;
      }
    });

    if (next == null && track < 0) {
      track = (60/Math.PI*Math.atan(track.toDouble()*Math.PI/60)).ceil();
      track = Math.max(-30, track);
      opacity = Math.max(0.925, opacity);
      scale = Math.max(scale, 1 - (1 - MIN_SCALE)*60/400);
      
      shadowRoot.querySelector('core-pages').style.boxShadow =
          'inset ${track.ceil()}px 0 70px -40px';
      track=0;
      /* This is overriden here for mobile devices to keep it out of Apple
       * patent waters.
       */
    }
    else if (prev == null && track > 0) {
      track = (60/Math.PI*Math.atan(track.toDouble()*Math.PI/60)).floor();
      track = Math.min(30, track);
      opacity = Math.max(0.925, opacity);
      scale = Math.max(scale, 1 - (1 - MIN_SCALE)*60/400);
      shadowRoot.querySelector('core-pages').style.boxShadow =
          'inset ${track.floor()}px 0 70px -40px';
      track=0;
      /* This is overriden here for mobile devices to keep it out of Apple
       * patent waters.
       */
                 
    }
    else {
      shadowRoot.querySelector('core-pages').style.boxShadow = null;
    }
    
    (event['target'] as Node).childNodes.forEach((div) {
      if (div is! DivElement) return;
      div.style.transform = 'translateX(${track}px) scale($scale)';
      div.style.opacity = '$opacity';
    });
    
    PaperTabs paperTabs = shadowRoot.querySelector('paper-tabs'); 
    var width = 100.0 / paperTabs.items.length; 
    var positionL = selected*width - track/400*width;
    width = Math.min(100-positionL,width);
    if (positionL < 0) {
      width += positionL;
      positionL = 0;
    }
    paperTabs.shadowRoot.querySelector('#selectionBar').style
      ..width = '$width%'
      ..left = '$positionL%';
    
    if (event['timeStamp'] != null) {
      if (lastTimestamp != null) {
        var speed = event['ddx'] / (event['timeStamp'] - lastTimestamp);
        if (speed.isFinite) trackSpeed = speed;
      }
      lastTimestamp = event['timeStamp'].toDouble();
    }
  }
  void trackEndPage(ev) {
    shadowRoot.querySelector('core-pages').classes..remove('dragging');

    var event = new JsObject.fromBrowserObject(ev);


    //var speed = event['ddx']/(event['timeStamp'] - lastTimestamp);
    //if (speed.isFinite) trackSpeed = speed;
    if (trackSpeed == null) trackSpeed = 0.0;
    var angle = Math.atan(trackSpeed.abs() * FLING_FACTOR);
    var coordA = Math.sin(angle) * 0.42;
    var coordB = Math.cos(angle) * 0.42;

    (event['target'] as Node).childNodes.forEach((div) {
      if (div is! DivElement) return;
      div.style.transform = null;
      div.style.opacity = null;
      div.style.transition = 'all ${NOMINAL_SWITCH_DURATION}s cubic-bezier($coordB, $coordA, 1, 1) 0s';
    });

    var next = (event['target'] as Node).nextNode;
    for ( ; next != null && next.nodeName != 'SECTION'; next = next.nextNode);
    if (next != null) next.childNodes.forEach((div) {
      if (div is! DivElement) return;
      div.style.transform = null;
      div.style.opacity = null;
      div.style.transition = 'all ${NOMINAL_SWITCH_DURATION}s cubic-bezier($coordB, $coordA, 1, 1) 0s';
    });

    var prev = (event['target'] as Node).previousNode;
    for ( ; prev != null &&
        prev.nodeName != 'SECTION'; prev = prev.previousNode);
    if (prev != null) prev.childNodes.forEach((div) {
      if (div is! DivElement) return;
      div.style.transform = null;
      div.style.opacity = null;
      div.style.transition = 'all ${NOMINAL_SWITCH_DURATION}s cubic-bezier($coordB, $coordA, 1, 1) 0s';
    });
    
    
    if (next == null && track < 0) {
      var trackOffset = track.toDouble() - (60/Math.PI*Math.atan(track.toDouble()*Math.PI/60));
      var trackTime = 1/(track.toDouble() - trackOffset).abs()*2;
      var angle = Math.atan(trackOffset.abs()/trackTime/2);
      if (trackTime > 0.5) {
        trackTime = 0.5;
        angle = 0;
      }
      var coordA = Math.sin(angle) * 0.42;
      var coordB = Math.cos(angle) * 0.42;
      (event['target'] as Node).childNodes.forEach((div) {
        if (div is! DivElement) return;
        div.style.transition = 'all ${trackTime}s cubic-bezier($coordB, $coordA, 1, 1) 0s';
      });
      
    }
    else if (prev == null && track > 0) {
      var trackOffset = track.toDouble() - (60/Math.PI*Math.atan(track.toDouble()*Math.PI/60));
      var trackTime = 1/(track.toDouble() - trackOffset).abs()*2;
      var angle = Math.atan(trackOffset.abs()/trackTime/2);
      if (trackTime > 0.5) {
        trackTime = 0.5;
        angle = 0;
      }
      var coordA = Math.sin(angle) * 0.42;
      var coordB = Math.cos(angle) * 0.42;
      (event['target'] as Node).childNodes.forEach((div) {
        if (div is! DivElement) return;
        div.style.transition = 'all ${trackTime}s cubic-bezier($coordB, $coordA, 1, 1) 0s';
      });
     }
    
    track += (trackSpeed * FLING_FACTOR).floor();
    if (track < -200 && next != null) {
      selected++;
    } 
    else if (track > 200 && prev != null) {
      selected--;
    } 
    else {
      selectedChanged(selected);
    }
    shadowRoot.querySelector('core-pages').style.boxShadow = null;
    
    new Future(() {
      PaperTabs paperTabs = shadowRoot.querySelector('paper-tabs'); 
    
      var selectionBar = paperTabs.shadowRoot.querySelector('#selectionBar');
      selectionBar.classes
        ..add('contract')
        ..remove('expand');
      var width = 100.0 / paperTabs.items.length; 
      var positionL = selected*width;
      selectionBar.style
        ..width = '$width%'
        ..left = '$positionL%';
    });

  }
}
