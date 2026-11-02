package scene.editor;

class CommandStack {
  public var canUndo(get, never) : Bool;
  public var canRedo(get, never) : Bool;
  public var isDirty(get, never) : Bool;
  public var undoCount(get, never) : Int;
  public var redoCount(get, never) : Int;
  public var nextUndoLabel(get, never) : Null<String>;
  public var nextRedoLabel(get, never) : Null<String>;
  // Sahnenin içeriği her değiştiğinde farklılaşır: otomatik yedek buna bakar.
  public var revision(get, never) : Int;

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

  // Otomatik yedekten dönen sahne diskteki dosyadan farklıdır.
  public function markUnsaved() {
    savedVersion = -1;
  }

  // Boşaltılan hücrenin adımları düşer, kalan adımlar başka nesnelerle ilgili olduğu için
  // geçerliliğini korur. Bu yüzden hücre boşaltmak geçmişi silmez.
  public function forget(match : Command->Bool) {
    var clean = !isDirty;
    var count = done.length;
    var keptDone = [], keptHistory = [], keptUndone = [];
    for (i in 0...count) {
      if (match(done[i])) continue;
      keptDone.push(done[i]);
      keptHistory.push(history[i]);
    }
    // history'nin sonu yinelenecek adımlardır: sıradaki adım undone listesinin sonundadır.
    var i = undone.length;
    var next = count;
    while (i-- > 0) {
      if (!match(undone[i])) {
        keptUndone.unshift(undone[i]);
        keptHistory.push(history[next]);
      }
      next++;
    }
    done = keptDone;
    undone = keptUndone;
    history = keptHistory;
    version = done.length == 0 ? 0 : history[done.length - 1];
    if (clean) savedVersion = version;
  }

  public function clear() {
    done = [];
    undone = [];
    history = [];
    version = 0;
    savedVersion = 0;
  }

  function get_revision() {
    return version;
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
