package scene;

// Karakterlerin çıkamayacağı alan, örneğin yürünmesi istenmeyen bir tepe. Köşeleri alt nesnedir.
@:component("nav_block")
class NavBlockArea extends PathMarker {
  static inline var SIDE = 20.;

  override public function color() : Int {
    return 0xE04040;
  }

  override public function title() : String {
    return "Yürünmez alan";
  }

  override public function initialPoints() : Array<Array<Float>> {
    return [[0, 0], [SIDE, 0], [SIDE, SIDE], [0, SIDE]];
  }

  override function isClosed() {
    return true;
  }

  override public function navShapes() {
    var points = [];
    for (point in waypoints()) {
      var at = point.worldPoint();
      points.push(at.x);
      points.push(at.y);
    }
    return points.length < 6 ? [] : [scene.nav.NavShapes.polygon(points)];
  }
}
