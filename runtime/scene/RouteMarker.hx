package scene;

// Rota: noktaları alt nesnelerdir, böylece gizmoyla taşınır ve prefab'a girer.
// Oyunun türü bundan türer ve kendi `@:component` kimliğini verir.
class RouteMarker extends PathMarker {
  @:editable("Kapalı rota") public var loop : Bool = false;

  override function isClosed() {
    return loop;
  }

  override function drawSegment(overlay : Overlay, tint : Int, a : h3d.Vector, b : h3d.Vector) {
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
