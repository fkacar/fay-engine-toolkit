package scene;

// Noktaları alt nesne olan işaretçi: gizmoyla taşınır, prefab'a girer. Rota ve alan bundan türer.
class PathMarker extends Marker {
  public static inline var WAYPOINT = "waypoint";

  public function waypoints() : Array<WaypointMarker> {
    var points = [];
    for (child in entity.children) {
      var point = child.getComponent(WaypointMarker);
      if (point != null) points.push(point);
    }
    return points;
  }

  // Menüden eklenince ilk noktalar, işaretçiye göre metre.
  public function initialPoints() : Array<Array<Float>> {
    return [[0, 0], [12, 0]];
  }

  function isClosed() {
    return false;
  }

  override function drawShape(overlay : Overlay, tint : Int, at : h3d.Vector) {
    var points = waypoints();
    for (i in 0...points.length) {
      if (i == points.length - 1 && !isClosed()) break;
      var a = points[i].worldPoint(), b = points[(i + 1) % points.length].worldPoint();
      overlay.line(a.x, a.y, a.z + 0.2, b.x, b.y, b.z + 0.2, tint);
      drawSegment(overlay, tint, a, b);
    }
  }

  function drawSegment(overlay : Overlay, tint : Int, a : h3d.Vector, b : h3d.Vector) {}
}
