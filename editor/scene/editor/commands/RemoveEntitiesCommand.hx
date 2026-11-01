package scene.editor.commands;

import scene.Entity;
import scene.SceneInstance;

class RemoveEntitiesCommand implements Command {
  public var label(default, null) = "Sil";

  var scene : SceneInstance;
  var entities : Array<Entity>;
  var detached : Array<DetachedEntity> = [];

  // Alt nesneler üst nesneyle birlikte gider, listede yalnızca en üstteki nesneler olmalı.
  public function new(scene : SceneInstance, entities : Array<Entity>) {
    this.scene = scene;
    this.entities = entities;
  }

  public function execute() {
    detached = [for (entity in entities) scene.detach(entity)];
  }

  public function undo() {
    var i = detached.length;
    while (i-- > 0) scene.attach(detached[i]);
    detached = [];
  }
}
