package scene.world;

import scene.world.TerrainSurface;

// Arazi modelinin üçgenlerini üstten bakışla hücrelerin köşelerine çizer. Her köşede en yüksek
// yüzey kalır: mağara veya köprünün altı yürünmez. Model dışında kalan köşeler eski yüksekliğini
// korur. Dört köşesi modelin altında kalan kareyi model çizer.
class TerrainModelBaker {
  public static inline var RESOLUTION = 90;

  // old: hücrenin model uygulanmadan önceki hali.
  // Üçgenleri ağırlık merkezinin düştüğü hücreye verir. Üçgen kesilmez: komşu iki hücre birlikte
  // yüklüyken her üçgen bir kez çizilir, sınırda yarık olmaz.
  public static function surfaces(world : WorldData, groups : Array<SurfaceGroup>) : Map<Int, TerrainSurface> {
    var result = new Map<Int, TerrainSurface>();
    for (group in groups) {
      var parts = new Map<Int, {group : SurfaceGroup, remap : Map<Int, Int>}>();
      var p = group.positions, indexes = group.indexes;
      var i = 0;
      while (i + 2 < indexes.length) {
        var a = indexes[i], b = indexes[i + 1], c = indexes[i + 2];
        i += 3;
        var cell = world.nearest((p[a * 3] + p[b * 3] + p[c * 3]) / 3, (p[a * 3 + 1] + p[b * 3 + 1] + p[c * 3 + 1]) / 3);
        var part = parts.get(cell);
        if (part == null) {
          part = {group: {texture: group.texture, positions: [], normals: [], uvs: [], indexes: []}, remap: new Map()};
          parts.set(cell, part);
          if (!result.exists(cell)) result.set(cell, new TerrainSurface());
          result.get(cell).groups.push(part.group);
        }
        for (vertex in [a, b, c]) {
          var local = part.remap.get(vertex);
          if (local == null) {
            local = Std.int(part.group.positions.length / 3);
            part.remap.set(vertex, local);
            for (k in 0...3) {
              part.group.positions.push(p[vertex * 3 + k]);
              part.group.normals.push(group.normals[vertex * 3 + k]);
            }
            part.group.uvs.push(group.uvs[vertex * 2]);
            part.group.uvs.push(group.uvs[vertex * 2 + 1]);
          }
          part.group.indexes.push(local);
        }
      }
    }
    return result;
  }

  // old: hücrenin model uygulanmadan önceki hali.
  public static function bake(world : WorldData, old : Int->Null<TerrainCell>, positions : Array<Float>, indexes : Array<Int>) : Map<Int, TerrainCell> {
    var size = world.cellSize, step = size / RESOLUTION, side = RESOLUTION + 1;
    var targets = new Map<Int, TerrainCell>();
    var hits = new Map<Int, haxe.ds.Vector<Float>>();
    function target(cell : Int) {
      if (!targets.exists(cell)) {
        var before = old(cell);
        targets.set(cell, before == null ? TerrainCell.flat(RESOLUTION) : before.resample(RESOLUTION));
        var grid = new haxe.ds.Vector<Float>(side * side);
        for (i in 0...side * side) grid[i] = Math.NEGATIVE_INFINITY;
        hits.set(cell, grid);
      }
      return hits.get(cell);
    }

    var i = 0;
    while (i + 2 < indexes.length) {
      var a = indexes[i] * 3, b = indexes[i + 1] * 3, c = indexes[i + 2] * 3;
      var ax = positions[a], ay = positions[a + 1], az = positions[a + 2];
      var bx = positions[b], by = positions[b + 1], bz = positions[b + 2];
      var cx = positions[c], cy = positions[c + 1], cz = positions[c + 2];
      i += 3;
      var area = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy);
      if (Math.abs(area) < 1e-12) continue;
      var minX = Math.min(ax, Math.min(bx, cx)), maxX = Math.max(ax, Math.max(bx, cx));
      var minY = Math.min(ay, Math.min(by, cy)), maxY = Math.max(ay, Math.max(by, cy));
      var fromX = Std.int(Math.max(0, Math.ceil((minX - world.left) / step))), toX = Std.int(Math.min(world.columns * RESOLUTION, Math.floor((maxX - world.left) / step)));
      var fromY = Std.int(Math.max(0, Math.ceil((minY - world.bottom) / step))), toY = Std.int(Math.min(world.rows * RESOLUTION, Math.floor((maxY - world.bottom) / step)));
      for (gy in fromY...toY + 1)
        for (gx in fromX...toX + 1) {
          var x = world.left + gx * step, y = world.bottom + gy * step;
          var u = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / area;
          var v = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / area;
          var w = 1 - u - v;
          if (u < -1e-6 || v < -1e-6 || w < -1e-6) continue;
          var z = u * az + v * bz + w * cz;
          // Hücre kenarındaki köşe iki hücreye de yazılır.
          for (column in edges(gx, world.columns))
            for (row in edges(gy, world.rows)) {
              var grid = target(world.id(column, row));
              var index = (gy - row * RESOLUTION) * side + gx - column * RESOLUTION;
              if (z > grid[index]) grid[index] = z;
            }
        }
    }

    for (cell => grid in hits) {
      var result = targets.get(cell);
      for (y in 0...side) for (x in 0...side) if (grid[y * side + x] != Math.NEGATIVE_INFINITY) result.setHeight(x, y, grid[y * side + x]);
      for (y in 0...RESOLUTION)
        for (x in 0...RESOLUTION) {
          var covered = true;
          for (corner in [[0, 0], [1, 0], [0, 1], [1, 1]]) if (grid[(y + corner[1]) * side + x + corner[0]] == Math.NEGATIVE_INFINITY) covered = false;
          if (covered) result.setLayer(x, y, TerrainCell.COVERED);
        }
    }
    return targets;
  }

  static function edges(vertex : Int, count : Int) {
    var cell = Std.int(vertex / RESOLUTION);
    var found = [];
    if (cell < count) found.push(cell);
    if (vertex % RESOLUTION == 0 && cell > 0) found.push(cell - 1);
    return found;
  }
}
