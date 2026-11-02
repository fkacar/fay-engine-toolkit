package scene.editor.commands;

import scene.Entity;
import scene.editor.commands.SetTransformCommand.Transform;

class SetParentCommand implements Command {
  public var label(default, null) = "Üst nesneyi değiştir";

  var entity : Entity;
  var parent : Null<Entity>;
  var previous : Null<Entity>;
  var previousIndex : Int;
  var before : Transform;
  var after : Null<Transform>;
  var keepPlace : Entity->Void;

  // keepPlace yeni üst nesnede dünya konumunu korur; sonucu redo için saklanır.
  public function new(entity : Entity, parent : Null<Entity>, keepPlace : Entity->Void) {
    this.entity = entity;
    this.parent = parent;
    this.keepPlace = keepPlace;
    previous = entity.parent;
    before = SetTransformCommand.capture(entity);
  }

  public function execute() {
    previousIndex = previous == null ? 0 : previous.children.indexOf(entity);
    entity.setParent(parent);
    if (after == null) {
      keepPlace(entity);
      after = SetTransformCommand.capture(entity);
    } else {
      SetTransformCommand.apply(entity, after);
    }
  }

  public function undo() {
    entity.setParent(previous);
    if (previous != null) {
      previous.children.remove(entity);
      previous.children.insert(previousIndex, entity);
    }
    SetTransformCommand.apply(entity, before);
  }

  public function touched() {
    return [for (item in [entity, parent, previous]) if (item != null) item];
  }
}
