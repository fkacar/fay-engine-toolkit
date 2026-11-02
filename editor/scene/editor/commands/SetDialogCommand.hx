package scene.editor.commands;

import scene.Entity;

class SetDialogCommand implements Command {
  public var label(default, null) : String;

  var store : DialogStore;
  public var id(default, null) : String;
  var before : Null<String>;
  var after : Null<String>;

  public function new(label : String, store : DialogStore, id : String, before : Null<String>, after : Null<String>) {
    this.label = label;
    this.store = store;
    this.id = id;
    this.before = before;
    this.after = after;
  }

  public function execute() {
    store.apply(id, after);
  }

  public function undo() {
    store.apply(id, before);
  }

  public function touched() {
    var none : Array<Entity> = [];
    return none;
  }
}
