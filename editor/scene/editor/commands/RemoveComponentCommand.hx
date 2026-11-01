package scene.editor.commands;

import scene.Component;
import scene.Entity;

class RemoveComponentCommand implements Command {
  public var label(default, null) = "Bileşeni kaldır";

  var entity : Entity;
  var component : Component;
  var index : Int;

  public function new(entity : Entity, component : Component) {
    this.entity = entity;
    this.component = component;
  }

  public function execute() {
    index = entity.components.indexOf(component);
    entity.removeComponent(component);
  }

  public function undo() {
    entity.addComponent(component, index);
  }
}
