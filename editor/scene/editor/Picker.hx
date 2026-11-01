package scene.editor;

import h3d.col.Bounds;
import h3d.col.Ray;
import h3d.scene.Mesh;
import h3d.scene.Object;

// Seçim fizik motoruna bağlı değildir, doğrudan görünen mesh'lere bakar.
class Picker {
  // `limit` görünen en uzak nokta: zeminin ardındaki nesneler tıklanamaz.
  public static function pick(scene : SceneInstance, ray : Ray, limit : Float) : Null<Entity> {
    var best = null, nearest = limit;
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
    // Gizli parçalar (kapalı seçim halkası gibi) tıklanmamalı.
    if (!object.visible) return -1;
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
    var polygon = Std.downcast(mesh.primitive, h3d.prim.Polygon);
    if (polygon != null && polygon.idx == null) return polygonDistance(mesh, polygon, ray);
    // Son çare: kutu. İndekssiz Polygon burada olmamalı, haritaya yayılan kutusu tüm tıklamaları yutar.
    return try mesh.getGlobalCollider().rayIntersection(ray, true) catch (e : Dynamic) reached;
  }

  // Heaps indekssiz Polygon'dan çarpışma verisi üretemez (birleştirilmiş kayalar, birimler).
  static function polygonDistance(mesh : Mesh, polygon : h3d.prim.Polygon, ray : Ray) : Float {
    var local = ray.clone();
    local.transform(mesh.getInvPos());
    var origin = new Vec3(local.px, local.py, local.pz), direction = new Vec3(local.lx, local.ly, local.lz);
    var points = polygon.points;
    var nearest = -1.;
    var i = 0;
    while (i + 2 < points.length) {
      var a = points[i], b = points[i + 1], c = points[i + 2];
      var hit = GizmoMath.rayTriangle(origin, direction, new Vec3(a.x, a.y, a.z), new Vec3(b.x, b.y, b.z), new Vec3(c.x, c.y, c.z));
      if (hit >= 0 && (nearest < 0 || hit < nearest)) nearest = hit;
      i += 3;
    }
    if (nearest < 0) return -1.;
    var point = new h3d.col.Point(origin.x + direction.x * nearest, origin.y + direction.y * nearest, origin.z + direction.z * nearest);
    point.transform(mesh.getAbsPos());
    return new Vec3(point.x - ray.px, point.y - ray.py, point.z - ray.pz).length();
  }
}
