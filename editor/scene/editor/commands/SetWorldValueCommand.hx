package scene.editor.commands;

import scene.Entity;

// Dünya dosyasındaki tek bir sayı, örneğin yürünebilir eğim.
class SetWorldValueCommand implements Command {
  public var label(default, null) : String;

  var write : Float->Void;
  var before : Float;
  var after : Float;

  public function new(label : String, write : Float->Void, before : Float, after : Float) {
    this.label = label;
    this.write = write;
    this.before = before;
    this.after = after;
  }

  public function execute() {
    write(after);
  }

  public function undo() {
    write(before);
  }

  public function touched() {
    var none : Array<Entity> = [];
    return none;
  }
}
