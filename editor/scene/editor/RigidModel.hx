package scene.editor;

import h3d.Vector;
import hxd.fmt.hmd.Data;

// İskeletsiz model (silah, eşya) için içe aktarma yardımcıları. Köşeler oyunun çizdiği eksende okunur (düğüm
// dönüşümleri uygulanmış: FBX eksen çevirisi ve birim ölçeği dahil).
// scaleTo: silah paketleri 1 birimlik kutuya sığdırılmış gelir; en uzun kenar ayardaki gerçek boya ölçeklenir.
// Tutamak tahmini GripEstimate'te (köşelerden; model verisine bağlı değil).
class RigidModel {

  // Modelin çizildiği eksende bütün köşeler.
  public static function points(hmd : Data) : Array<Vector> {
    var found = [];
    for (index in 0...hmd.models.length) {
      var model = hmd.models[index];
      if (model.geometry < 0) continue;
      var matrix = worldOf(hmd, index);
      var geometry = hmd.geometries[model.geometry];
      var format = geometry.vertexFormat;
      var position = format.getInput("position");
      if (position == null || position.precision != F32) continue;
      var stride = format.strideBytes, offset = format.calculateInputOffset("position");
      for (v in 0...geometry.vertexCount) {
        var at = geometry.vertexPosition + v * stride + offset;
        var point = new Vector(hmd.data.getFloat(at), hmd.data.getFloat(at + 4), hmd.data.getFloat(at + 8));
        found.push(point.transformed(matrix));
      }
    }
    return found;
  }

  // En uzun kenar length metre olacak şekilde kök düğümler ölçeklenir. Uygulanan çarpan döner (1: değişmedi).
  public static function scaleTo(hmd : Data, length : Float) : Float {
    var box = bounds(points(hmd));
    var longest = Math.max(box.max.x - box.min.x, Math.max(box.max.y - box.min.y, box.max.z - box.min.z));
    if (longest < 1e-6) return 1;
    var k = length / longest;
    for (model in hmd.models) if (model.parent < 0) {
      var p = model.position;
      p.x *= k;
      p.y *= k;
      p.z *= k;
      p.sx *= k;
      p.sy *= k;
      p.sz *= k;
    }
    return k;
  }

  public static function bounds(points : Array<Vector>) : {min : Vector, max : Vector} {
    var min = new Vector(1e30, 1e30, 1e30), max = new Vector(-1e30, -1e30, -1e30);
    for (p in points) {
      min.x = Math.min(min.x, p.x); min.y = Math.min(min.y, p.y); min.z = Math.min(min.z, p.z);
      max.x = Math.max(max.x, p.x); max.y = Math.max(max.y, p.y); max.z = Math.max(max.z, p.z);
    }
    return {min: min, max: max};
  }

  static function worldOf(hmd : Data, index : Int) : h3d.Matrix {
    var matrix = hmd.models[index].position.toMatrix();
    var parent = hmd.models[index].parent;
    while (parent >= 0) {
      matrix.multiply(matrix, hmd.models[parent].position.toMatrix());
      parent = hmd.models[parent].parent;
    }
    return matrix;
  }
}
