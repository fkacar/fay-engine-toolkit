package scene.world;

import scene.GroundHeight;

// Yüklü hücrelerin yüksekliği. Yüklü olmayan hücre 0 yüksekliğinde sayılır.
class WorldTerrain implements GroundHeight {
  public var world(default, null) : WorldData;

  var cells = new Map<Int, TerrainCell>();

  public function new(world : WorldData) {
    this.world = world;
  }

  public function get(cell : Int) : Null<TerrainCell> {
    return cells.get(cell);
  }

  public function set(cell : Int, terrain : TerrainCell) {
    cells.set(cell, terrain);
  }

  public function remove(cell : Int) {
    cells.remove(cell);
  }

  // Yüklü hücreler, artan sırayla (sonradan bağlanan bir sistem, ör. fizik, var olanları kurar).
  public function loaded() : Array<Int> {
    var list = [for (cell in cells.keys()) cell];
    list.sort((a, b) -> a - b);
    return list;
  }

  public function contains(x : Float, y : Float) {
    return world.cellAt(x, y) != WorldData.OUTSIDE;
  }

  // Dünya ızgarasındaki köşe. Hücre kenarındaki köşe iki, kesişimdeki dört hücrede durur.
  public function cellsOfVertex(gx : Int, gy : Int) : Array<Int> {
    var resolution = world.resolution;
    var cells = [];
    for (column in spans(gx, resolution, world.columns))
      for (row in spans(gy, resolution, world.rows))
        cells.push(world.id(column, row));
    return cells;
  }

  // Ortak köşeler dünya çözünürlüğündeki hücrelerde tutulur; model altındaki hücre ayrı örneklenir.
  public function vertexHeight(gx : Int, gy : Int) : Float {
    for (cell in cellsOfVertex(gx, gy)) {
      var data = cells.get(cell);
      if (data == null || data.resolution != world.resolution) continue;
      return data.height(gx - world.columnOf(cell) * world.resolution, gy - world.rowOf(cell) * world.resolution);
    }
    return 0;
  }

  public function setVertexHeight(gx : Int, gy : Int, value : Float) {
    for (cell in cellsOfVertex(gx, gy)) {
      var data = cells.get(cell);
      if (data != null && data.resolution == world.resolution) data.setHeight(gx - world.columnOf(cell) * world.resolution, gy - world.rowOf(cell) * world.resolution, value);
    }
  }

  static function spans(vertex : Int, resolution : Int, count : Int) {
    var cell = Std.int(vertex / resolution);
    var found = [];
    if (cell < count) found.push(cell);
    if (vertex % resolution == 0 && cell > 0) found.push(cell - 1);
    return found;
  }

  // Üçgenlerin gerçek yüzeyini izler, böylece nesneler karelerin içine gömülmez. Arazi modeli
  // altındaki hücre daha sık örneklenir, bu yüzden çözünürlük hücreden okunur.
  public function heightAt(x : Float, y : Float) {
    var size = world.cellSize;
    var cx = Math.max(0, Math.min(x - world.left, world.width - 0.001));
    var cy = Math.max(0, Math.min(y - world.bottom, world.height - 0.001));
    var column = Std.int(cx / size), row = Std.int(cy / size);
    var data = cells.get(world.id(column, row));
    if (data == null) return 0.;
    var resolution = data.resolution;
    var gx = Math.min((cx - column * size) / size * resolution, resolution - 0.0001);
    var gy = Math.min((cy - row * size) / size * resolution, resolution - 0.0001);
    var ix = Std.int(gx), iy = Std.int(gy);
    var fx = gx - ix, fy = gy - iy;
    var h00 = data.height(ix, iy), h11 = data.height(ix + 1, iy + 1);
    if (fx > fy) {
      var h10 = data.height(ix + 1, iy);
      return h00 + (h10 - h00) * fx + (h11 - h10) * fy;
    }
    var h01 = data.height(ix, iy + 1);
    return h00 + (h11 - h01) * fx + (h01 - h00) * fy;
  }
}
