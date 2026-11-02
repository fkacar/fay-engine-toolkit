package scene.editor;

import h3d.Matrix;
import h3d.Vector;
import h3d.col.Bounds;
import h3d.col.Point;
import h3d.col.Ray;
import haxe.io.Path;
import scene.Entity;
import scene.GroundHeight;
import scene.Guid;
import scene.Marker;
import scene.PathMarker;
import scene.data.Prefabs;
import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.editor.commands.AddEntitiesCommand;
import scene.editor.commands.GroupCommand;
import scene.editor.commands.RemoveEntitiesCommand;
import scene.editor.commands.SetParentCommand;
import scene.editor.commands.SetTransformCommand;
import scene.editor.commands.SyncPrefabsCommand;
import sys.FileSystem;
import sys.io.File;

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
  static inline var PREFAB_DIRECTORY = "res/prefabs";
  static inline var PREFAB_SUFFIX = ".prefab.json";
  static inline var WAYPOINT_GAP = 12.;

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
    var removable = roots.filter(entity -> !entity.isPrefabPart);
    if (removable.length < roots.length) editor.show("Prefab parçası silinemez, prefab'ı açıp orada sil");
    if (removable.length == 0) return;
    editor.commands.execute(new RemoveEntitiesCommand(editor.scene, removable));
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
      if (entity.isPrefabPart) {
        editor.show("Prefab parçası taşınamaz, prefab'ı açıp orada düzenle");
        continue;
      }
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
    if (isPrefab(path)) {
      dropPrefab(path, ray);
      return;
    }
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

  public function isPrefab(path : String) {
    return StringTools.endsWith(path, PREFAB_SUFFIX);
  }

  public function prefabFiles() : Array<String> {
    if (!FileSystem.exists(PREFAB_DIRECTORY)) return [];
    var names = FileSystem.readDirectory(PREFAB_DIRECTORY).filter(isPrefab);
    names.sort(Reflect.compare);
    return [for (name in names) 'prefabs/$name'];
  }

  // Seçili nesne dosyaya yazılır ve yerine o dosyanın instance'ı konur.
  public function makePrefab(name : String) : Bool {
    var root = editor.selection.primary;
    if (root == null || editor.selection.items.length != 1) {
      editor.show("Prefab için tek nesne seç", true);
      return false;
    }
    if (root.instanceRoot != null) {
      editor.show(root.isPrefabPart ? "Prefab parçasından prefab yapılamaz" : "Bu nesne zaten prefab", true);
      return false;
    }
    var clean = SceneDocument.cleanName(name);
    if (clean == "") {
      editor.show("Geçerli bir prefab adı yaz", true);
      return false;
    }
    var path = '$PREFAB_DIRECTORY/$clean$PREFAB_SUFFIX';
    if (FileSystem.exists(path)) {
      editor.show('Bu adda bir prefab var: $clean', true);
      return false;
    }

    var scene = editor.scene;
    var data = scene.toDataOf([root]);
    var head = Lambda.find(data.entities, item -> item.id == root.id);
    // Kök kimliği korunur, sahnedeki referanslar kırılmasın.
    var instance = new EntityData(root.id, root.name);
    instance.parent = head.parent;
    instance.active = head.active;
    instance.position = head.position;
    instance.rotation = head.rotation;
    instance.scale = head.scale;
    instance.prefab = 'prefabs/$clean$PREFAB_SUFFIX';
    head.parent = null;
    head.position = [0, 0, 0];
    head.rotation = [0, 0, 0];
    head.scale = [1, 1, 1];

    if (!FileSystem.exists(PREFAB_DIRECTORY)) FileSystem.createDirectory(PREFAB_DIRECTORY);
    File.saveContent(path, SceneFormat.write(data));
    AssetImporter.forgetMissingFiles();

    var add = new AddEntitiesCommand(scene, [instance], "Prefab yap");
    editor.commands.execute(new GroupCommand("Prefab yap", [new RemoveEntitiesCommand(scene, [root]), add]));
    editor.selection.set([add.entities[0]]);
    editor.show('Prefab oluşturuldu: $path');
    return true;
  }

  // Farklar prefab dosyasına yazılır, aynı prefab'ın tüm kopyaları güncellenir.
  public function applyPrefab(root : Entity) {
    var changes = editor.scene.overridesOf(root);
    var path = 'res/${root.prefab}';
    if (changes.length == 0) return;
    if (!FileSystem.exists(path)) {
      editor.show('Prefab dosyası yok: $path', true);
      return;
    }
    var text = File.getContent(path);
    var prefab = SceneFormat.read(text);
    Prefabs.applyToPrefab(prefab, changes);
    var file = {path: root.prefab, before: text, after: SceneFormat.write(prefab), write: content -> File.saveContent(path, content)};
    editor.commands.execute(new SyncPrefabsCommand("Prefab'a uygula", editor.scene, root, file));
    editor.show('Prefab güncellendi: $path');
  }

  public function revertPrefab(root : Entity) {
    editor.commands.execute(new SyncPrefabsCommand("Farkları sil", editor.scene, root));
    editor.show("Prefab'a dönüldü");
  }

  public function openPrefab(root : Entity) {
    editor.requestOpen('res/${root.prefab}');
  }

  public function placeableMarkers() : Array<Marker> {
    var registry = editor.scene.registry;
    var markers = [for (type in registry.currentTypes()) Std.downcast(registry.create(type), Marker)];
    return markers.filter(marker -> marker != null && marker.isPlaceable());
  }

  public function addMarker(type : String, ?extra : Array<ComponentData>, ?name : String) {
    var place = groundUnder(editor.viewport.centerRay());
    var item = new EntityData(Guid.make(), name != null ? name : cast(editor.scene.registry.create(type), Marker).title());
    // Zemini bilen işaretçide z, zeminden yüksekliktir.
    item.position = [place.x, place.y, editor.scene.service(GroundHeight) == null ? place.z : 0];
    item.components.push(new ComponentData(type));
    if (extra != null) for (data in extra) item.components.push(data);
    var items = [item];
    var path = Std.downcast(editor.scene.registry.create(type), PathMarker);
    if (path != null) for (point in path.initialPoints()) items.push(waypointData(item.id, point[0], point[1]));
    add(items, "İşaretçi ekle");
  }

  // Yeni nokta son noktanın ilerisine, rota yönünde gelir.
  public function addWaypoint(route : PathMarker) {
    var points = route.waypoints();
    var x = 0., y = 0.;
    if (points.length > 0) {
      var last = points[points.length - 1].entity;
      x = last.x + WAYPOINT_GAP;
      y = last.y;
      if (points.length > 1) {
        var before = points[points.length - 2].entity;
        var dx = last.x - before.x, dy = last.y - before.y;
        var size = Math.sqrt(dx * dx + dy * dy);
        if (size > 0.01) {
          x = last.x + dx / size * WAYPOINT_GAP;
          y = last.y + dy / size * WAYPOINT_GAP;
        }
      }
    }
    add([waypointData(route.entity.id, x, y)], "Rota noktası ekle");
  }

  function waypointData(parent : String, x : Float, y : Float) {
    var item = new EntityData(Guid.make(), "Nokta");
    item.parent = parent;
    item.position = [x, y, 0];
    item.components.push(new ComponentData(PathMarker.WAYPOINT));
    return item;
  }

  function dropPrefab(path : String, ray : Ray) {
    var place = groundUnder(ray);
    var item = new EntityData(Guid.make(), Path.withoutDirectory(path).split(".")[0]);
    item.position = [place.x, place.y, place.z];
    item.prefab = path;
    add([item], "Prefab ekle");
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
  // Prefab parçasının kimliği `kök/parça` biçimindedir, kök kopyalanınca parça da yeni köke geçer.
  function copiedId(ids : Map<String, String>, id : String) : Null<String> {
    if (ids.exists(id)) return ids.get(id);
    var root = id.split(Prefabs.SEPARATOR)[0];
    return ids.exists(root) && root != id ? ids.get(root) + id.substr(root.length) : null;
  }

  function freshCopies(text : String) {
    var items = SceneFormat.read(text).entities;
    var ids = new Map<String, String>();
    for (item in items) {
      var id = Guid.make();
      ids.set(item.id, id);
      item.id = id;
    }
    for (item in items) {
      var parent = item.parent == null ? null : copiedId(ids, item.parent);
      if (parent != null) {
        item.parent = parent;
      } else {
        if (item.parent != null && editor.scene.find(item.parent) == null) item.parent = null;
        item.name += " (kopya)";
        item.position[0] += PASTE_OFFSET;
        item.position[1] += PASTE_OFFSET;
      }
      for (component in item.components)
        for (name => value in component.fields)
          if (Std.isOfType(value, String) && copiedId(ids, value) != null) component.fields.set(name, copiedId(ids, value));
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
