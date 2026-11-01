package scene.editor;

import h3d.Matrix;
import h3d.Vector;
import h3d.col.Bounds;
import h3d.col.Point;
import h3d.col.Ray;
import haxe.io.Path;
import scene.Entity;
import scene.Guid;
import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.editor.commands.AddEntitiesCommand;
import scene.editor.commands.GroupCommand;
import scene.editor.commands.RemoveEntitiesCommand;
import scene.editor.commands.SetParentCommand;
import scene.editor.commands.SetTransformCommand;

typedef AssetType = {
  var component : String;
  var field : String;
}

// Panellerin, kısayolların ve menünün ortak kullandığı sahne işlemleri.
class SceneActions {
  static inline var PASTE_OFFSET = 2.;
  static inline var GROUND_SEARCH = 500.;
  static inline var DROP_DISTANCE = 30.;
  static inline var FOCUS_RADIUS = 6.;
  static inline var GROUND_MARGIN = 0.05;

  // Zemin oyuna özeldir (arazi, kat...). Oyun bunu verir, verilmezse z = 0 düzlemi kullanılır.
  public var groundRay : Null<Ray->Null<Point>>;

  var editor : Editor;
  var assetTypes = new Map<String, AssetType>();
  var clipboard : Null<String>;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  // Bu uzantıdaki dosya sahneye bırakılınca verilen bileşen eklenir, yol `field` alanına yazılır.
  public function addAssetType(extension : String, component : String, field : String) {
    assetTypes.set(extension.toLowerCase(), {component: component, field: field});
  }

  public function createEmpty(?parent : Entity) {
    var item = new EntityData(Guid.make(), "Yeni nesne");
    if (parent != null) {
      item.parent = parent.id;
    } else {
      var place = groundUnder(editor.viewport.centerRay());
      item.position = [place.x, place.y, place.z];
    }
    add([item], "Nesne ekle");
  }

  public function remove() {
    var roots = editor.selection.roots();
    if (roots.length == 0) return;
    editor.commands.execute(new RemoveEntitiesCommand(editor.scene, roots));
    editor.selection.clear();
  }

  public function copy() {
    var roots = editor.selection.roots();
    if (roots.length == 0) return;
    clipboard = SceneFormat.write(editor.scene.toDataOf(roots));
    editor.show('Kopyalandı: ${roots.length} nesne');
  }

  public function paste() {
    if (clipboard == null) {
      editor.show("Pano boş");
      return;
    }
    add(freshCopies(clipboard), "Yapıştır");
  }

  public function duplicate() {
    var roots = editor.selection.roots();
    if (roots.length == 0) return;
    add(freshCopies(SceneFormat.write(editor.scene.toDataOf(roots))), "Çoğalt");
  }

  public function reparent(entities : Array<Entity>, parent : Null<Entity>) {
    var moves : Array<Command> = [];
    for (entity in entities) {
      if (entity.parent == parent || (parent != null && parent.isInside(entity))) continue;
      moves.push(new SetParentCommand(entity, parent, keepPlace(entity.object.getAbsPos().clone())));
    }
    if (moves.length > 0) editor.commands.execute(new GroupCommand("Üst nesneyi değiştir", moves));
  }

  public function snapToGround() {
    if (!editor.canEdit()) {
      editor.show("Birlikte düzenlemek için önce kilitle");
      return;
    }
    var moves : Array<Command> = [];
    for (entity in editor.selection.roots()) {
      var offset = groundOffset(entity);
      if (offset == null) continue;
      var before = SetTransformCommand.capture(entity);
      shift(entity, new Vec3(0, 0, offset));
      var after = SetTransformCommand.capture(entity);
      if (!SetTransformCommand.same(before, after)) moves.push(new SetTransformCommand(entity, before, after));
    }
    if (moves.length > 0) editor.commands.execute(new GroupCommand("Zemine yapıştır", moves));
    else if (editor.selection.items.length == 0) editor.show("Önce bir nesne seç");
  }

  public function dropAsset(path : String, ray : Ray) {
    var type = assetTypes.get(Path.extension(path).toLowerCase());
    if (type == null) {
      editor.show('Bu dosya sahneye eklenemez: $path', true);
      return;
    }
    var hit = groundHit(ray);
    var place = hit == null ? ray.getPoint(DROP_DISTANCE) : hit;
    var item = new EntityData(Guid.make(), Path.withoutExtension(Path.withoutDirectory(path)));
    item.position = [place.x, place.y, place.z];
    var component = new ComponentData(type.component);
    component.fields.set(type.field, path);
    item.components.push(component);

    var entity = add([item], "Model ekle")[0];
    if (hit == null) return;
    var offset = groundOffset(entity);
    if (offset != null) shift(entity, new Vec3(0, 0, offset));
  }

  public function focus() {
    var roots = editor.selection.roots();
    if (roots.length == 0) return;
    var box = new Bounds();
    for (entity in roots) box.add(Picker.bounds(entity));
    if (box.isEmpty()) {
      editor.viewport.camera.focus(Gizmo.centerOf(roots), FOCUS_RADIUS);
      return;
    }
    var center = box.getCenter();
    var radius = Math.max(Math.max(box.xSize, box.ySize), box.zSize) * 0.5;
    editor.viewport.camera.focus(new Vec3(center.x, center.y, center.z), radius);
  }

  public function groundUnder(ray : Ray) : Point {
    var hit = groundHit(ray);
    return hit == null ? ray.getPoint(DROP_DISTANCE) : hit;
  }

  public function groundHit(ray : Ray) : Null<Point> {
    return groundRay == null ? flatGround(ray) : groundRay(ray);
  }

  // Işının zemine kadarki uzunluğu. Kamera adımı bayat mesafeye değil buna bakar.
  public function surfaceDistance(ray : Ray) : Null<Float> {
    var hit = groundHit(ray);
    return hit == null ? null : distanceAlong(ray, hit);
  }

  // Görünen en uzak nokta. Düz varsayılan zemin çizilmez, nesneleri de gizlemez.
  public function visibleDistance(ray : Ray) : Float {
    var hit = groundRay == null ? null : groundRay(ray);
    return hit == null ? Math.POSITIVE_INFINITY : distanceAlong(ray, hit) + GROUND_MARGIN;
  }

  function add(items : Array<EntityData>, label : String) {
    var command = new AddEntitiesCommand(editor.scene, items, label);
    editor.commands.execute(command);
    var created = command.entities;
    editor.selection.set(created.filter(entity -> entity.parent == null || created.indexOf(entity.parent) < 0));
    return created;
  }

  // Yazıp okumak derin kopya verir; kimlikler yenilenir, kopya kendi içine bağlı kalır.
  function freshCopies(text : String) {
    var items = SceneFormat.read(text).entities;
    var ids = new Map<String, String>();
    for (item in items) {
      var id = Guid.make();
      ids.set(item.id, id);
      item.id = id;
    }
    for (item in items) {
      var inside = item.parent != null && ids.exists(item.parent);
      if (inside) {
        item.parent = ids.get(item.parent);
      } else {
        if (item.parent != null && editor.scene.find(item.parent) == null) item.parent = null;
        item.name += " (kopya)";
        item.position[0] += PASTE_OFFSET;
        item.position[1] += PASTE_OFFSET;
      }
      for (component in item.components)
        for (name => value in component.fields)
          if (Std.isOfType(value, String) && ids.exists(value)) component.fields.set(name, ids.get(value));
    }
    return items;
  }

  // Yeni üst nesnede dünya konumu korunur. Bileşen konumu düzeltiyorsa (zemine oturma gibi)
  // kalan fark ölçülüp yerel değere eklenir.
  function keepPlace(world : Matrix) : Entity->Void {
    return entity -> {
      var local = new Matrix();
      local.multiply3x4(world, entity.object.parent.getInvPos());
      var position = local.getPosition(), scale = local.getScale(), rotation = local.getEulerAngles();
      entity.setScale(scale.x, scale.y, scale.z);
      entity.setRotation(degrees(rotation.x), degrees(rotation.y), degrees(rotation.z));
      entity.setPosition(position.x, position.y, position.z);
      var target = world.getPosition();
      shift(entity, new Vec3(target.x, target.y, target.z).sub(Gizmo.worldPosition(entity)));
    };
  }

  function shift(entity : Entity, world : Vec3) {
    var local = new Vector(world.x, world.y, world.z);
    local.transform3x3(entity.object.parent.getInvPos());
    entity.setPosition(entity.x + local.x, entity.y + local.y, entity.z + local.z);
  }

  // Nesnenin en alt noktası ile zemin arasındaki dünya yüksekliği farkı.
  function groundOffset(entity : Entity) : Null<Float> {
    var at = Gizmo.worldPosition(entity);
    var box = Picker.bounds(entity);
    var bottom = box.isEmpty() ? at.z : box.zMin;
    var top = box.isEmpty() ? at.z : box.zMax;
    var hit = groundHit(Ray.fromValues(at.x, at.y, top + GROUND_SEARCH, 0, 0, -1));
    return hit == null ? null : hit.z - bottom;
  }

  static function distanceAlong(ray : Ray, point : Point) {
    return new Vec3(point.x - ray.px, point.y - ray.py, point.z - ray.pz).length();
  }

  static function flatGround(ray : Ray) : Null<Point> {
    var hit = GizmoMath.planeHit(new Vec3(ray.px, ray.py, ray.pz), new Vec3(ray.lx, ray.ly, ray.lz), new Vec3(), new Vec3(0, 0, 1));
    return hit == null ? null : new Point(hit.x, hit.y, hit.z);
  }

  static inline function degrees(radians : Float) {
    return radians * 180 / Math.PI;
  }
}
