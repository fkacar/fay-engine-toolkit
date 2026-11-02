package scene.world;

import scene.Entity;
import scene.SceneInstance;

// Oyunda yalnızca kameranın yakınındaki hücreler yüklü kalır. Arazi daha geniş bir halkada
// tutulur, çünkü uzaktan da görünür. Takılma olmasın diye karede tek hücre açılır.
class CellStreamer {
  // Hücre, yüklendiği halkanın bir dışına çıkınca boşalır: sınırda gezen kamera hücreleri
  // sürekli açıp kapatmaz.
  static inline var UNLOAD_MARGIN = 1;

  public var objectRadius = 2;
  public var terrainRadius = 4;

  var state : WorldState;
  var scene : SceneInstance;
  var withObjects : Bool;
  var center = WorldData.OUTSIDE;
  var loaded = new Map<Int, Array<Entity>>();
  var terrain = new Map<Int, Bool>();
  var waiting : Array<Int> = [];

  public function new(state : WorldState, scene : SceneInstance, withObjects : Bool) {
    this.state = state;
    this.scene = scene;
    this.withObjects = withObjects;
  }

  public function isLoaded(cell : Int) {
    return loaded.exists(cell);
  }

  public function loadedCount() {
    return Lambda.count(loaded);
  }

  // Başlangıçta oyun açılmadan önce hepsi birden yüklenir.
  public function start(x : Float, y : Float) {
    if (withObjects) scene.load(state.objects(WorldData.GLOBAL));
    moveTo(state.data.cellAt(x, y));
    while (waiting.length > 0) loadNext();
  }

  public function update(x : Float, y : Float) {
    var cell = state.data.cellAt(x, y);
    if (cell != WorldData.OUTSIDE && cell != center) moveTo(cell);
    if (withObjects) unloadFar();
    if (waiting.length > 0) loadNext();
  }

  function moveTo(cell : Int) {
    center = cell == WorldData.OUTSIDE ? state.data.id(Std.int(state.data.columns / 2), Std.int(state.data.rows / 2)) : cell;
    var data = state.data;
    var nearTerrain = data.around(center, terrainRadius);
    for (old in [for (key in terrain.keys()) key])
      if (nearTerrain.indexOf(old) < 0) {
        terrain.remove(old);
        state.unloadTerrain(old);
      }
    for (cell in nearTerrain)
      if (!terrain.exists(cell)) {
        terrain.set(cell, true);
        state.loadTerrain(cell);
      }
    if (!withObjects) return;

    waiting = data.around(center, objectRadius).filter(cell -> !loaded.exists(cell));
  }

  function unloadFar() {
    var kept = state.data.around(center, objectRadius + UNLOAD_MARGIN);
    function isNear(x : Float, y : Float) {
      return kept.indexOf(state.data.nearest(x, y)) >= 0;
    }
    for (cell in [for (key in loaded.keys()) key]) {
      if (kept.indexOf(cell) >= 0 || isHeld(cell, isNear)) continue;
      unload(cell);
    }
  }

  function isHeld(cell : Int, isNear : (Float, Float) -> Bool) {
    for (entity in loaded.get(cell))
      for (component in entity.components)
        if (component.keepsCell(isNear)) return true;
    return false;
  }

  function loadNext() {
    var cell = waiting.shift();
    loaded.set(cell, scene.stream(state.objects(cell).entities));
    state.loadScatter(cell);
  }

  function unload(cell : Int) {
    for (root in loaded.get(cell).filter(entity -> entity.parent == null)) scene.destroyEntity(root);
    loaded.remove(cell);
    state.unloadScatter(cell);
  }
}
