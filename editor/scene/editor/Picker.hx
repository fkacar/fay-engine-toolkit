package scene.editor;

import h3d.col.Bounds;
import h3d.col.Ray;
import h3d.scene.Mesh;
import h3d.scene.Object;

// Seçim fizik motoruna bağlı değildir, doğrudan görünen mesh'lere bakar.
class Picker {
  public static function pick(scene : SceneInstance, ray : Ray) : Null<Entity> {
    var best = null, nearest = Math.POSITIVE_INFINITY;
    for (entity in scene.entities) {
      if (!entity.isShown()) continue;
      var distance = rayDistance(entity, ray);
      if (distance < 0 || distance >= nearest) continue;
      nearest = distance;
      best = entity;
    }
    return best;
  }

  // Alt nesneler hariç, nesnenin kendi görseli.
  public static function bounds(entity : Entity) : Bounds {
    var box = new Bounds();
    for (visual in visuals(entity)) visual.getBounds(box);
    return box;
  }

  static function visuals(entity : Entity) {
    var list = [];
    for (i in 0...entity.object.numChildren) {
      var child = entity.object.getChildAt(i);
      if (!Lambda.exists(entity.children, other -> other.object == child)) list.push(child);
    }
    for (component in entity.components) list = list.concat(component.visuals());
    return list;
  }

  static function rayDistance(entity : Entity, ray : Ray) : Float {
    var nearest = -1.;
    for (visual in visuals(entity)) {
      var distance = objectDistance(visual, ray);
      if (distance >= 0 && (nearest < 0 || distance < nearest)) nearest = distance;
    }
    return nearest;
  }

  static function objectDistance(object : Object, ray : Ray) : Float {
    var nearest = -1.;
    var mesh = Std.downcast(object, Mesh);
    if (mesh != null) nearest = meshDistance(mesh, ray);
    for (i in 0...object.numChildren) {
      var distance = objectDistance(object.getChildAt(i), ray);
      if (distance >= 0 && (nearest < 0 || distance < nearest)) nearest = distance;
    }
    return nearest;
  }

  static function meshDistance(mesh : Mesh, ray : Ray) : Float {
    var box = mesh.primitive.getBounds().clone();
    box.transform(mesh.getAbsPos());
    var reached = box.rayIntersection(ray, true);
    if (reached < 0) return -1.;
    // Bazı primitive türleri çarpışma verisi üretmez, o zaman kutu yeterlidir.
    return try mesh.getGlobalCollider().rayIntersection(ray, true) catch (e : Dynamic) reached;
  }
}
