package scene.editor.commands;

import scene.Entity;
import scene.world.WorldData;

// Genel nesne hücreye bağlı değildir, her zaman yüklüdür.
class SetGlobalCommand implements Command {
  public var label(default, null) = "Her zaman yüklü";

  var entity : Entity;
  var before : Int;
  var isGlobal : Bool;

  public function new(entity : Entity, isGlobal : Bool) {
    this.entity = entity;
    this.isGlobal = isGlobal;
    before = entity.cell;
  }

  public function execute() {
    entity.cell = isGlobal ? WorldData.GLOBAL : WorldData.OUTSIDE;
  }

  public function undo() {
    entity.cell = before;
  }

  public function touched() {
    return [entity];
  }
}
