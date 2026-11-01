package scene.editor.commands;

import scene.Component;

class SetFieldCommand implements Command {
  public var label(default, null) : String;

  var component : Component;
  var field : String;
  var before : Dynamic;
  var after : Dynamic;

  public function new(component : Component, field : String, before : Dynamic, after : Dynamic, ?label : String) {
    this.component = component;
    this.field = field;
    this.before = before;
    this.after = after;
    this.label = label == null ? field : label;
  }

  public function execute() {
    apply(after);
  }

  public function undo() {
    apply(before);
  }

  function apply(value : Dynamic) {
    component.writeField(field, value);
    component.refresh();
  }
}
