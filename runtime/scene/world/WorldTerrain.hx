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

  public function vertexHeight(gx : Int, gy : Int) : Float {
    for (cell in cellsOfVertex(gx, gy)) {
      var data = cells.get(cell);
      if (data == null) continue;
      return data.height(gx - world.columnOf(cell) * world.resolution, gy - world.rowOf(cell) * world.resolution);
    }
    return 0;
  }

  public function setVertexHeight(gx : Int, gy : Int, value : Float) {
    for (cell in cellsOfVertex(gx, gy)) {
      var data = cells.get(cell);
      if (data != null) data.setHeight(gx - world.columnOf(cell) * world.resolution, gy - world.rowOf(cell) * world.resolution, value);
    }
  }

  static function spans(vertex : Int, resolution : Int, count : Int) {
    var cell = Std.int(vertex / resolution);
    var found = [];
    if (cell < count) found.push(cell);
    if (vertex % resolution == 0 && cell > 0) found.push(cell - 1);
    return found;
  }

  // Üçgenlerin gerçek yüzeyini izler, böylece nesneler karelerin içine gömülmez.
  public function heightAt(x : Float, y : Float) {
    var resolution = world.resolution;
    var gx = Math.max(0, Math.min((x - world.left) / world.step, world.columns * resolution - 0.001));
    var gy = Math.max(0, Math.min((y - world.bottom) / world.step, world.rows * resolution - 0.001));
    var qx = Std.int(gx), qy = Std.int(gy);
    var data = cells.get(world.id(Std.int(qx / resolution), Std.int(qy / resolution)));
    if (data == null) return 0.;
    var ix = qx % resolution, iy = qy % resolution;
    var fx = gx - qx, fy = gy - qy;
    var h00 = data.height(ix, iy), h11 = data.height(ix + 1, iy + 1);
    if (fx > fy) {
      var h10 = data.height(ix + 1, iy);
      return h00 + (h10 - h00) * fx + (h11 - h10) * fy;
    }
    var h01 = data.height(ix, iy + 1);
    return h00 + (h11 - h01) * fx + (h01 - h00) * fy;
  }
}
