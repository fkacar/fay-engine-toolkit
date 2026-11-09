package scene.story;

import scene.story.Dialog.DialogNode;

// Oyunda açık konuşma. Koşul ve olay düğümleri oyuncuya görünmez, kendiliğinden geçilir.
class DialogRunner {
  static inline var STEP_LIMIT = 200;

  public var speaker(default, null) = "";
  public var text(default, null) = "";
  public var choices(default, null) : Array<String> = [];
  // Seçeneklerin kaynak metni ve çeviri anahtarı (görev testleri seçeneği her dilde bulur).
  public var sourceChoices(default, null) : Array<String> = [];
  public var choiceKeys(default, null) : Array<String> = [];
  public var finished(default, null) = false;
  public var id(get, never) : String;

  var dialog : Dialog;
  var story : Story;
  var current : Null<DialogNode>;
  // Ekranda kalan son satır (seçenekteyken de görünür): dil değişince yeniden çevrilir.
  var line : Null<DialogNode>;

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
    if (story.log != null) story.log.add("secim", {dialog: dialog.id, node: current.id, index: index + 1, text: current.choices[index].text});
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
          line = current;
          showLine();
          choices = [];
          if (story.log != null) story.log.add("satir", {dialog: dialog.id, node: current.id, speaker: speaker, text: text});
          return;
        case Dialog.CHOICES:
          var node = current;
          showChoices(node);
          if (story.log != null) story.log.add("secenekler", {dialog: dialog.id, node: current.id, choices: choices});
          return;
        case Dialog.CONDITION:
          var value = current.kind == Dialog.ITEM ? story.state.count(current.name)
            : current.kind == Dialog.STANDING ? story.standing(current.name) : story.state.flag(current.name);
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
    if (story.log != null) story.log.add("diyalog_bitti", {dialog: dialog.id});
  }

  // Dil değişti: bulunduğu düğümün yazıları (son satır, seçenekler) yeni dille. İlerlemez, günlüğe yazmaz.
  public function retranslate() {
    if (line != null) showLine();
    if (current != null && current.type == Dialog.CHOICES) showChoices(current);
  }

  function showLine() {
    var who = line.speaker == null ? "" : line.speaker;
    speaker = who == "" || story.speakerName == null ? who : story.speakerName(who);
    text = translated(Dialog.lineKey(line), line.text == null ? "" : line.text);
  }

  function showChoices(node : DialogNode) {
    sourceChoices = [for (choice in node.choices) choice.text];
    choiceKeys = [for (choice in node.choices) Dialog.choiceKey(node, choice)];
    choices = [for (i in 0...node.choices.length) translated(choiceKeys[i], sourceChoices[i])];
  }

  function translated(key : String, source : String) : String {
    return source == "" || story.translateLine == null ? source : story.translateLine(dialog.id, key, source);
  }

  function get_id() {
    return dialog.id;
  }
}
