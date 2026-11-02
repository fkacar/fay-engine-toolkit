package scene.editor.commands;

// Birlikte yapılan değişiklikler undo'ya tek adım olarak girer.
class GroupCommand implements Command {
  public var label(default, null) : String;

  var commands : Array<Command>;

  public function new(label : String, commands : Array<Command>) {
    this.label = label;
    this.commands = commands;
  }

  public function execute() {
    for (command in commands) command.execute();
  }

  public function undo() {
    var i = commands.length;
    while (i-- > 0) commands[i].undo();
  }

  public function touched() {
    return [for (command in commands) for (entity in command.touched()) entity];
  }
}
