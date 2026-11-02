package scene.editor.commands;

import scene.Entity;

// Tablo değişikliği: tablonun önceki ve sonraki hali saklanır.
class SetTableCommand implements Command {
  public var label(default, null) : String;

  var store : DataStore;
  public var name(default, null) : String;
  var before : Null<String>;
  var after : Null<String>;

  public function new(label : String, store : DataStore, name : String, before : Null<String>, after : Null<String>) {
    this.label = label;
    this.store = store;
    this.name = name;
    this.before = before;
    this.after = after;
  }

  public function execute() {
    store.apply(name, after);
  }

  public function undo() {
    store.apply(name, before);
  }

  public function touched() {
    var none : Array<Entity> = [];
    return none;
  }
}
