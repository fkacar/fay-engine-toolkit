package scene.editor.commands;

import scene.Entity;

typedef Transform = {
  var position : Array<Float>;
  var rotation : Array<Float>;
  var scale : Array<Float>;
}

class SetTransformCommand implements Command {
  public var label(default, null) = "Dönüşüm";

  var entity : Entity;
  var before : Transform;
  var after : Transform;

  public static function capture(entity : Entity) : Transform {
    return {
      position: [entity.x, entity.y, entity.z],
      rotation: [entity.rotX, entity.rotY, entity.rotZ],
      scale: [entity.scaleX, entity.scaleY, entity.scaleZ],
    };
  }

  public function new(entity : Entity, before : Transform, after : Transform) {
    this.entity = entity;
    this.before = before;
    this.after = after;
  }

  public function execute() {
    apply(after);
  }

  public function undo() {
    apply(before);
  }

  function apply(state : Transform) {
    entity.setPosition(state.position[0], state.position[1], state.position[2]);
    entity.setRotation(state.rotation[0], state.rotation[1], state.rotation[2]);
    entity.setScale(state.scale[0], state.scale[1], state.scale[2]);
  }
}
