package scene.editor.commands;

import scene.Entity;

class SetActiveCommand implements Command {
  public var label(default, null) = "Oyunda göster/gizle";

  var entity : Entity;
  var value : Bool;

  public function new(entity : Entity, value : Bool) {
    this.entity = entity;
    this.value = value;
  }

  public function execute() {
    entity.active = value;
  }

  public function undo() {
    entity.active = !value;
  }

  public function touched() {
    return [entity];
  }
}
