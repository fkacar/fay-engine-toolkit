package scene;

// Rota: noktaları alt nesnelerdir, böylece gizmoyla taşınır ve prefab'a girer.
// Oyunun türü bundan türer ve kendi `@:component` kimliğini verir.
class RouteMarker extends Marker {
  public static inline var WAYPOINT = "waypoint";

  @:editable("Kapalı rota") public var loop : Bool = false;

  public function waypoints() : Array<WaypointMarker> {
    var points = [];
    for (child in entity.children) {
      var point = child.getComponent(WaypointMarker);
      if (point != null) points.push(point);
    }
    return points;
  }

  override function drawShape(overlay : Overlay, tint : Int, at : h3d.Vector) {
    var points = waypoints();
    for (i in 0...points.length) {
      if (i == points.length - 1 && !loop) break;
      var a = points[i].worldPoint(), b = points[(i + 1) % points.length].worldPoint();
      overlay.line(a.x, a.y, a.z + 0.2, b.x, b.y, b.z + 0.2, tint);
      drawArrow(overlay, tint, a, b);
    }
  }

  function drawArrow(overlay : Overlay, tint : Int, a : h3d.Vector, b : h3d.Vector) {
    var dx = b.x - a.x, dy = b.y - a.y;
    var size = Math.sqrt(dx * dx + dy * dy);
    if (size < 0.01) return;
    dx /= size;
    dy /= size;
    var mx = (a.x + b.x) * 0.5, my = (a.y + b.y) * 0.5, mz = (a.z + b.z) * 0.5 + 0.2;
    overlay.line(mx, my, mz, mx - dx - dy * 0.5, my - dy + dx * 0.5, mz, tint);
    overlay.line(mx, my, mz, mx - dx + dy * 0.5, my - dy - dx * 0.5, mz, tint);
  }
}
