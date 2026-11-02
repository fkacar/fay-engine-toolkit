package scene;

// Çarpışma şekli. Yalnızca veridir, fizik motorundan bağımsız saklanır: motor seçilince oyun
// tarafı bu alanları okur. "model" şekli nesnenin kendi mesh'ini kullanır.
@:component("collider")
class ColliderComponent extends Component {
  static inline var COLOR = 0xFF40E0A0;

  @:editable("Şekil") @:choice("kutu", "kapsul", "model") public var shape : String = "kutu";
  @:editable("Genişlik", 0.01, 500) public var width : Float = 2;
  @:editable("Derinlik", 0.01, 500) public var depth : Float = 2;
  @:editable("Yükseklik", 0.01, 500) public var height : Float = 2;
  @:editable("Yarıçap", 0.01, 100) public var radius : Float = 0.5;
  @:editable("Yerden yükseklik") public var offset : Float = 0;

  override public function drawOverlay(overlay : Overlay, selected : Bool) {
    if (!selected) return;
    var frame = entity.object.getAbsPos();
    switch (shape) {
      case "kutu": OverlayShapes.box(overlay, frame, width, depth, offset, offset + height, COLOR);
      case "kapsul": OverlayShapes.capsule(overlay, frame, radius, offset, offset + height, COLOR);
      default: drawModelBounds(overlay);
    }
  }

  override public function navShapes() {
    var frame = entity.object.getAbsPos();
    if (shape == "kutu") return [scene.nav.NavShapes.box(frame, width, depth)];
    if (shape == "kapsul") return [scene.nav.NavShapes.circle(frame.tx, frame.ty, radius)];
    var bounds = entity.object.getBounds();
    var center = bounds.getCenter();
    return [scene.nav.NavShapes.box(h3d.Matrix.T(center.x, center.y, 0), bounds.xSize, bounds.ySize)];
  }

  function drawModelBounds(overlay : Overlay) {
    var bounds = entity.object.getBounds();
    var frame = new h3d.Matrix();
    frame.initTranslation(bounds.getCenter().x, bounds.getCenter().y, bounds.zMin);
    OverlayShapes.box(overlay, frame, bounds.xSize, bounds.ySize, 0, bounds.zSize, COLOR);
  }
}
