package scene.editor;

class GizmoMath {
  static inline var PARALLEL = 1e-5;

  // Işının eksen doğrusuna en yakın olduğu yerin eksen üzerindeki konumu.
  public static function axisParam(rayPos : Vec3, rayDir : Vec3, axisPos : Vec3, axisDir : Vec3) : Null<Float> {
    var between = axisPos.sub(rayPos);
    var cross = rayDir.cross(axisDir);
    var denominator = cross.dot(cross);
    if (denominator < PARALLEL) return null;
    return between.cross(rayDir).dot(cross) / denominator;
  }

  public static function planeHit(rayPos : Vec3, rayDir : Vec3, planePos : Vec3, normal : Vec3) : Null<Vec3> {
    var facing = rayDir.dot(normal);
    if (Math.abs(facing) < PARALLEL) return null;
    var distance = planePos.sub(rayPos).dot(normal) / facing;
    return distance < 0 ? null : rayPos.add(rayDir.scale(distance));
  }

  public static function snap(value : Float, step : Float) {
    return step <= 0 ? value : Math.round(value / step) * step;
  }

  public static function segmentDistance(px : Float, py : Float, ax : Float, ay : Float, bx : Float, by : Float) {
    var dx = bx - ax, dy = by - ay;
    var size = dx * dx + dy * dy;
    var t = size == 0 ? 0. : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / size));
    var ox = ax + dx * t - px, oy = ay + dy * t - py;
    return Math.sqrt(ox * ox + oy * oy);
  }

  // İşaretli açı (radyan): eksene doğru bakınca saat yönünün tersi pozitiftir.
  public static function signedAngle(from : Vec3, to : Vec3, axis : Vec3) {
    return Math.atan2(from.cross(to).dot(axis), from.dot(to));
  }
}
