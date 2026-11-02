package scene.editor.commands;

import scene.Entity;
import scene.world.ScatterCell;
import scene.world.TerrainCell;
import scene.world.WorldState;

// Fırça darbesinin hücre kopyaları. Darbe tek adımda geri alınır.
class WorldStrokeCommand implements Command implements CellCommand {
  public var label(default, null) : String;

  var state : WorldState;
  var terrainBefore : Map<Int, TerrainCell>;
  var terrainAfter = new Map<Int, TerrainCell>();
  var scatterBefore : Map<Int, ScatterCell>;
  var scatterAfter = new Map<Int, ScatterCell>();
  var changed : Array<Int>->Array<Int>->Void;

  function new(label : String, state : WorldState, terrain : Map<Int, TerrainCell>, scatter : Map<Int, ScatterCell>, changed : Array<Int>->Array<Int>->Void) {
    this.label = label;
    this.state = state;
    this.changed = changed;
    terrainBefore = terrain;
    scatterBefore = scatter;
  }

  public static function capture(label : String, state : WorldState, terrain : Map<Int, TerrainCell>, scatter : Map<Int, ScatterCell>, changed : Array<Int>->Array<Int>->Void) {
    var command = new WorldStrokeCommand(label, state, terrain, scatter, changed);
    for (cell in terrain.keys()) command.terrainAfter.set(cell, state.terrain.get(cell).clone());
    for (cell in scatter.keys()) command.scatterAfter.set(cell, state.scatter.get(cell).clone());
    return command;
  }

  public function execute() {
    restore(terrainAfter, scatterAfter);
  }

  public function undo() {
    restore(terrainBefore, scatterBefore);
  }

  public function touched() {
    var none : Array<Entity> = [];
    return none;
  }

  public function touchesCell(cell : Int) {
    return terrainBefore.exists(cell) || scatterBefore.exists(cell);
  }

  function restore(terrain : Map<Int, TerrainCell>, scatter : Map<Int, ScatterCell>) {
    for (cell => data in terrain) {
      state.terrain.set(cell, data.clone());
      state.view.terrainChanged(cell);
    }
    for (cell => data in scatter) {
      state.scatter.set(cell, data.clone());
      state.view.scatterChanged(cell);
    }
    changed([for (cell in terrain.keys()) cell], [for (cell in scatter.keys()) cell]);
  }
}
