package scene.world;

import scene.data.SceneData;
import scene.data.SceneFormat;

// Dünyanın yüklü verisi. Oyun ve editör aynı veriyi kullanır, ikisi de `read` ile okur.
class WorldState {
  public var data(default, null) : WorldData;
  public var terrain(default, null) : WorldTerrain;
  public var scatter(default, null) = new Map<Int, ScatterCell>();
  public var environment(default, null) : EnvironmentData;
  public var view : Null<WorldView>;
  public var read : String->Null<String>;

  public function new(data : WorldData, read : String->Null<String>) {
    this.data = data;
    this.read = read;
    terrain = new WorldTerrain(data);
    reloadEnvironment();
  }

  public function reloadEnvironment() {
    var text = read(data.environmentPath());
    environment = text == null ? new EnvironmentData() : EnvironmentData.read(text);
    if (view != null) view.environmentChanged();
  }

  public function loadTerrain(cell : Int) {
    var text = read(data.path(cell, WorldData.TERRAIN_SUFFIX));
    terrain.set(cell, text == null ? TerrainCell.flat(data.resolution) : TerrainCell.read(text));
    if (view != null) view.terrainChanged(cell);
  }

  public function loadAllTerrain() {
    for (cell in data.cells()) loadTerrain(cell);
  }

  public function unloadTerrain(cell : Int) {
    terrain.remove(cell);
    if (view != null) view.terrainRemoved(cell);
  }

  public function loadScatter(cell : Int) {
    var text = read(data.path(cell, WorldData.SCATTER_SUFFIX));
    scatter.set(cell, text == null ? new ScatterCell() : ScatterCell.read(text));
    if (view != null) view.scatterChanged(cell);
  }

  public function unloadScatter(cell : Int) {
    scatter.remove(cell);
    if (view != null) view.scatterRemoved(cell);
  }

  public function objects(cell : Int) : SceneData {
    var text = read(data.path(cell, WorldData.OBJECTS_SUFFIX));
    return text == null ? new SceneData(SceneFormat.VERSION) : SceneFormat.read(text);
  }
}
