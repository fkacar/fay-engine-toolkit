package scene.editor;

class CommandStack {
  public var canUndo(get, never) : Bool;
  public var canRedo(get, never) : Bool;
  public var isDirty(get, never) : Bool;
  public var undoCount(get, never) : Int;
  public var redoCount(get, never) : Int;
  public var nextUndoLabel(get, never) : Null<String>;
  public var nextRedoLabel(get, never) : Null<String>;

  var done : Array<Command> = [];
  var undone : Array<Command> = [];
  var version = 0;
  var nextVersion = 1;
  var history : Array<Int> = [];
  var savedVersion = 0;

  public function new() {}

  public function execute(command : Command) {
    command.execute();
    done.push(command);
    undone = [];
    history = history.slice(0, done.length - 1);
    version = nextVersion++;
    history.push(version);
  }

  public function undo() {
    if (!canUndo) return;
    var command = done.pop();
    command.undo();
    undone.push(command);
    version = done.length == 0 ? 0 : history[done.length - 1];
  }

  public function redo() {
    if (!canRedo) return;
    var command = undone.pop();
    command.execute();
    done.push(command);
    version = history[done.length - 1];
  }

  public function markSaved() {
    savedVersion = version;
  }

  public function clear() {
    done = [];
    undone = [];
    history = [];
    version = 0;
    savedVersion = 0;
  }

  function get_canUndo() {
    return done.length > 0;
  }

  function get_canRedo() {
    return undone.length > 0;
  }

  function get_isDirty() {
    return version != savedVersion;
  }

  function get_undoCount() {
    return done.length;
  }

  function get_redoCount() {
    return undone.length;
  }

  function get_nextUndoLabel() {
    return canUndo ? done[done.length - 1].label : null;
  }

  function get_nextRedoLabel() {
    return canRedo ? undone[undone.length - 1].label : null;
  }
}
