package scene;

import h3d.col.Point;
import h3d.scene.Mesh;

// Oyun mantığının haritada işaretlediği yer. Oyunda görünmez, editörde tıklanabilir bir nokta
// ve çizgilerle gösterilir. Yeni tür, bu sınıftan türeyip kaydedilen bir bileşendir.
class Marker extends Component {
  static inline var HANDLE_SIZE = 0.6;
  static inline var LABEL_HEIGHT = 1.2;
  static inline var SELECTED_ALPHA = 0xFF000000;
  static inline var NORMAL_ALPHA = 0xE0000000;
  static inline var RGB = 0xFFFFFF;

  // Görünüm menüsündeki filtre: kapalı türler çizilmez ve tıklanmaz.
  public static var hiddenTypes = new Map<String, Bool>();

  static var sphere : h3d.prim.Sphere;

  var handle : Null<Mesh>;

  public function color() : Int {
    return 0xFFFFFF;
  }

  // Menüde ve yeni nesnenin adında görünür.
  public function title() : String {
    return componentId();
  }

  // Menüden doğrudan eklenebilir mi? Rota noktası gibi türler kendi başına eklenmez.
  public function isPlaceable() {
    return true;
  }

  public function isFiltered() {
    return hiddenTypes.exists(componentId());
  }

  public function applyFilter() {
    if (handle != null) handle.visible = !isFiltered();
  }

  public function worldPoint() {
    return entity.object.getAbsPos().getPosition();
  }

  override function onCreate() {
    snapToGround();
    if (entity.scene.mode != Editor) return;
    if (sphere == null) {
      sphere = new h3d.prim.Sphere(1, 12, 8);
      sphere.addNormals();
    }
    handle = new Mesh(sphere, entity.object);
    handle.setScale(HANDLE_SIZE);
    handle.z = HANDLE_SIZE;
    handle.material.mainPass.enableLights = false;
    handle.material.shadows = false;
    handle.material.color.setColor(0xFF000000 | color());
    applyFilter();
  }

  override function onDestroy() {
    if (handle != null) handle.remove();
    handle = null;
  }

  override function onEntityMoved() {
    snapToGround();
  }

  override public function drawOverlay(overlay : Overlay, selected : Bool) {
    if (isFiltered()) return;
    var tint = (selected ? SELECTED_ALPHA : NORMAL_ALPHA) | (color() & RGB);
    var at = worldPoint();
    overlay.label(at.x, at.y, at.z + HANDLE_SIZE * 2 + LABEL_HEIGHT * 0.5, entity.name, tint);
    drawShape(overlay, tint, at);
  }

  function drawShape(overlay : Overlay, tint : Int, at : h3d.Vector) {}

  // Boyutlar ölçekten etkilenmez: alanların gerçek değeri Inspector'daki sayılardır.
  function flatFrame(at : h3d.Vector) {
    var world = entity.object.getAbsPos();
    var frame = new h3d.Matrix();
    frame.initRotationZ(Math.atan2(world._12, world._11));
    frame.translate(at.x, at.y, at.z);
    return frame;
  }

  function snapToGround() {
    var ground : GroundHeight = entity.scene.service(GroundHeight);
    if (ground == null) return;
    var parent = entity.object.parent;
    var base = parent.localToGlobal(new Point(entity.x, entity.y, 0));
    entity.object.z = ground.heightAt(base.x, base.y) - base.z + entity.z;
  }
}
