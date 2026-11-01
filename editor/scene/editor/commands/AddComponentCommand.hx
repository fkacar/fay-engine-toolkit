package scene.editor.commands;

import scene.Component;
import scene.Entity;

class AddComponentCommand implements Command {
  public var label(default, null) = "Bileşen ekle";

  var entity : Entity;
  var component : Component;

  public function new(entity : Entity, component : Component) {
    this.entity = entity;
    this.component = component;
  }

  public function execute() {
    entity.addComponent(component);
  }

  public function undo() {
    entity.removeComponent(component);
  }
}
