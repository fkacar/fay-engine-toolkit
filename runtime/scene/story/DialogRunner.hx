package scene.story;

import scene.story.Dialog.DialogNode;

// Oyunda açık konuşma. Koşul ve olay düğümleri oyuncuya görünmez, kendiliğinden geçilir.
class DialogRunner {
  static inline var STEP_LIMIT = 200;

  public var speaker(default, null) = "";
  public var text(default, null) = "";
  public var choices(default, null) : Array<String> = [];
  public var finished(default, null) = false;

  var dialog : Dialog;
  var story : Story;
  var current : Null<DialogNode>;

  public function new(dialog : Dialog, story : Story) {
    this.dialog = dialog;
    this.story = story;
    current = dialog.start();
    settle();
  }

  // Satırda devam eder; seçenekte bir şey yapmaz, seçim beklenir.
  public function next() {
    if (current != null && current.type == Dialog.LINE) go(current.next);
  }

  public function choose(index : Int) {
    if (current == null || current.type != Dialog.CHOICES || index < 0 || index >= current.choices.length) return;
    go(current.choices[index].next);
  }

  function go(id : Null<Int>) {
    current = id == null ? null : dialog.node(id);
    settle();
  }

  function settle() {
    var steps = 0;
    while (current != null && steps++ < STEP_LIMIT) {
      switch (current.type) {
        case Dialog.LINE:
          speaker = current.speaker == null ? "" : current.speaker;
          text = current.text == null ? "" : current.text;
          choices = [];
          return;
        case Dialog.CHOICES:
          choices = [for (choice in current.choices) choice.text];
          return;
        case Dialog.CONDITION:
          var value = current.kind == Dialog.ITEM ? story.state.count(current.name) : story.state.flag(current.name);
          current = dialog.node(value >= (current.value == null ? 1 : current.value) ? current.yes : current.no);
        case Dialog.EVENT:
          var event = current.event;
          current = current.next == null ? null : dialog.node(current.next);
          if (event != null && event != "") story.emit(event);
        case Dialog.END:
          current = null;
        default:
          current = current.next == null ? null : dialog.node(current.next);
      }
    }
    finished = true;
  }
}
