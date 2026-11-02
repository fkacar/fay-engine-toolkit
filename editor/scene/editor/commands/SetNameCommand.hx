package scene.editor.commands;

import scene.Entity;

class SetNameCommand implements Command {
  public var label(default, null) = "Yeniden adlandır";

  var entity : Entity;
  var before : String;
  var after : String;

  public function new(entity : Entity, before : String, after : String) {
    this.entity = entity;
    this.before = before;
    this.after = after;
  }

  public function execute() {
    entity.name = after;
  }

  public function undo() {
    entity.name = before;
  }

  public function touched() {
    return [entity];
  }
}
