package scene.editor.commands;

import scene.Entity;
import scene.SceneInstance;
import scene.data.SceneData.EntityData;

class AddEntitiesCommand implements Command {
  public var label(default, null) : String;
  public var entities(default, null) : Array<Entity> = [];

  var scene : SceneInstance;
  var items : Array<EntityData>;
  var detached : Array<DetachedEntity> = [];

  public function new(scene : SceneInstance, items : Array<EntityData>, label : String) {
    this.scene = scene;
    this.items = items;
    this.label = label;
  }

  public function execute() {
    if (entities.length == 0) {
      entities = scene.instantiate(items);
      return;
    }
    var i = detached.length;
    while (i-- > 0) scene.attach(detached[i]);
    detached = [];
  }

  public function undo() {
    for (entity in entities) if (scene.contains(entity) && !isChild(entity)) detached.push(scene.detach(entity));
  }

  function isChild(entity : Entity) {
    return entity.parent != null && entities.indexOf(entity.parent) >= 0;
  }

  public function touched() {
    return entities;
  }
}
