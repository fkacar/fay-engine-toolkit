package scene.world;

// Yüklü olmayan hücrelerin de yüksekliği: WorldTerrain yalnızca yüklü hücreleri bilir (yüklü olmayanı 0 sayar). Uzak
// katman (sahnede olmayan gruplar) bütün dünyada yürür, yokuşu görmesi gerekir. Hücrenin arazisi ilk gerektiğinde diskten
// okunur ve saklanır (yol bulma gibi, NavWorld). Hücre yüklüyse onun yüksekliği kullanılır (editörde değişmiş olabilir).
class DiskHeights {
  var state : WorldState;
  var own : WorldTerrain;
  var read = new Map<Int, Bool>();

  public function new(state : WorldState) {
    this.state = state;
    own = new WorldTerrain(state.data);
  }

  // Diskten okunan hücreyi unutur (hücrenin arazisi değişti).
  public function forget(cell : Int) {
    read.remove(cell);
    own.remove(cell);
  }

  public function heightAt(x : Float, y : Float) : Float {
    var world = state.data, size = world.cellSize;
    var cx = Math.max(0, Math.min(x - world.left, world.width - 0.001));
    var cy = Math.max(0, Math.min(y - world.bottom, world.height - 0.001));
    var cell = world.id(Std.int(cx / size), Std.int(cy / size));
    if (state.terrain.get(cell) != null) return state.terrain.heightAt(x, y);
    if (!read.exists(cell)) {
      read.set(cell, true);
      var text = state.read(world.path(cell, WorldData.TERRAIN_SUFFIX));
      own.set(cell, text == null ? TerrainCell.flat(world.resolution) : TerrainCell.read(text));
    }
    return own.heightAt(x, y);
  }
}
