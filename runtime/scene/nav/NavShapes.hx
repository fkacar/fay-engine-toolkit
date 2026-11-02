package scene.nav;

import scene.nav.NavCell;

// Nesnenin dünya matrisinden yürünemeyen alanını çıkarır.
class NavShapes {
  public static function box(frame : h3d.Matrix, sizeX : Float, sizeY : Float) : NavShape {
    var scaleX = Math.sqrt(frame._11 * frame._11 + frame._12 * frame._12);
    var scaleY = Math.sqrt(frame._21 * frame._21 + frame._22 * frame._22);
    return {x: frame.tx, y: frame.ty, halfX: sizeX * scaleX * 0.5, halfY: sizeY * scaleY * 0.5, angle: Math.atan2(frame._12, frame._11), isRound: false};
  }

  public static function polygon(points : Array<Float>) : NavShape {
    return {x: points[0], y: points[1], halfX: 0, halfY: 0, angle: 0, isRound: false, points: points};
  }

  public static function circle(x : Float, y : Float, radius : Float) : NavShape {
    return {x: x, y: y, halfX: radius, halfY: radius, angle: 0, isRound: true};
  }
}
