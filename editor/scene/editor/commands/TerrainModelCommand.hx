package scene.editor.commands;

import scene.Entity;
import scene.world.TerrainCell;
import scene.world.TerrainModels;
import scene.world.TerrainSurface;
import scene.world.WorldData.TerrainModel;
import scene.world.WorldState;

typedef CellState = {
  var terrain : TerrainCell;
  var surface : Null<TerrainSurface>;
}

// Arazi modelini eklemek, değiştirmek veya kaldırmak. Yalnızca gerçekten değişen hücreler
// tutulur: aynı model yeniden uygulanınca hiçbir hücre değişmez.
class TerrainModelCommand implements Command implements CellCommand {
  public var label(default, null) : String;

  var state : WorldState;
  var modelsBefore : Array<TerrainModel>;
  var modelsAfter : Array<TerrainModel>;
  var before : Map<Int, CellState>;
  var after : Map<Int, CellState>;
  var changed : Array<Int>->Void;

  public function new(label : String, state : WorldState, modelsAfter : Array<TerrainModel>, before : Map<Int, CellState>,
      after : Map<Int, CellState>, changed : Array<Int>->Void) {
    this.label = label;
    this.state = state;
    this.modelsBefore = TerrainModels.copy(state.data.terrainModels);
    this.modelsAfter = TerrainModels.copy(modelsAfter);
    this.before = before;
    this.after = after;
    this.changed = changed;
  }

  public function execute() {
    apply(modelsAfter, after);
  }

  public function undo() {
    apply(modelsBefore, before);
  }

  public function touched() {
    var none : Array<Entity> = [];
    return none;
  }

  public function touchesCell(cell : Int) {
    return before.exists(cell);
  }

  function apply(models : Array<TerrainModel>, cells : Map<Int, CellState>) {
    state.data.terrainModels = TerrainModels.copy(models);
    for (cell => item in cells) {
      state.terrain.set(cell, item.terrain.clone());
      if (item.surface == null) state.surfaces.remove(cell);
      else state.surfaces.set(cell, item.surface);
      state.view.terrainChanged(cell);
    }
    changed([for (cell in cells.keys()) cell]);
  }
}
