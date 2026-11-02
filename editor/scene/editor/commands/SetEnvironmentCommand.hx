package scene.editor.commands;

import scene.Entity;
import scene.world.EnvironmentData;
import scene.world.WorldState;

class SetEnvironmentCommand implements Command {
  public var label(default, null) : String;

  var state : WorldState;
  var before : EnvironmentData;
  var after : EnvironmentData;
  var edited : Void->Void;

  public function new(label : String, state : WorldState, before : EnvironmentData, after : EnvironmentData, edited : Void->Void) {
    this.label = label;
    this.state = state;
    this.before = before;
    this.after = after;
    this.edited = edited;
  }

  public function execute() {
    apply(after);
  }

  public function undo() {
    apply(before);
  }

  public function touched() {
    var none : Array<Entity> = [];
    return none;
  }

  function apply(values : EnvironmentData) {
    state.environment.assign(values);
    state.view.environmentChanged();
    edited();
  }
}
