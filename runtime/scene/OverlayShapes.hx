package scene;

import h3d.Matrix;
import h3d.col.Point;

// Şekiller `frame` matrisinin uzayında verilir: taban z = 0, nesne döndükçe şekil de döner.
class OverlayShapes {
  static inline var CIRCLE_STEPS = 40;

  public static function box(overlay : Overlay, frame : Matrix, width : Float, depth : Float, bottom : Float, top : Float, color : Int) {
    var x = width * 0.5, y = depth * 0.5;
    var corners = [[-x, -y], [x, -y], [x, y], [-x, y]];
    for (i in 0...4) {
      var a = corners[i], b = corners[(i + 1) % 4];
      line(overlay, frame, a[0], a[1], bottom, b[0], b[1], bottom, color);
      if (top == bottom) continue;
      line(overlay, frame, a[0], a[1], top, b[0], b[1], top, color);
      line(overlay, frame, a[0], a[1], bottom, a[0], a[1], top, color);
    }
  }

  public static function circle(overlay : Overlay, frame : Matrix, radius : Float, z : Float, color : Int) {
    for (i in 0...CIRCLE_STEPS) {
      var a = i * Math.PI * 2 / CIRCLE_STEPS, b = (i + 1) * Math.PI * 2 / CIRCLE_STEPS;
      line(overlay, frame, Math.cos(a) * radius, Math.sin(a) * radius, z, Math.cos(b) * radius, Math.sin(b) * radius, z, color);
    }
  }

  public static function capsule(overlay : Overlay, frame : Matrix, radius : Float, bottom : Float, top : Float, color : Int) {
    var low = bottom + radius, high = Math.max(top - radius, low);
    circle(overlay, frame, radius, low, color);
    circle(overlay, frame, radius, high, color);
    for (side in [[radius, 0.], [-radius, 0.], [0., radius], [0., -radius]])
      line(overlay, frame, side[0], side[1], low, side[0], side[1], high, color);
    for (axis in [[1., 0.], [0., 1.]]) {
      arc(overlay, frame, axis, radius, high, 1, color);
      arc(overlay, frame, axis, radius, low, -1, color);
    }
  }

  static function arc(overlay : Overlay, frame : Matrix, axis : Array<Float>, radius : Float, z : Float, up : Float, color : Int) {
    var half = Std.int(CIRCLE_STEPS / 2);
    for (i in 0...half) {
      var a = i * Math.PI / half, b = (i + 1) * Math.PI / half;
      line(overlay, frame, axis[0] * Math.cos(a) * radius, axis[1] * Math.cos(a) * radius, z + Math.sin(a) * radius * up,
        axis[0] * Math.cos(b) * radius, axis[1] * Math.cos(b) * radius, z + Math.sin(b) * radius * up, color);
    }
  }

  static function line(overlay : Overlay, frame : Matrix, x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, color : Int) {
    var a = new Point(x1, y1, z1), b = new Point(x2, y2, z2);
    a.transform(frame);
    b.transform(frame);
    overlay.line(a.x, a.y, a.z, b.x, b.y, b.z, color);
  }
}
