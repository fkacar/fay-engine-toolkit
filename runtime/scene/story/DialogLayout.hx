package scene.story;

import scene.story.Dialog.DialogNode;

// Diyalog düğümlerinin yerleşimi. Konumlar ekran netliğinden bağımsız birimdedir: Retina Mac'te
// ve Windows'ta aynı dosya aynı görünür. Yerleştir ekranda ölçülen boyu kullanmaz, içerikten
// hesaplar; aynı diyalog her makinede aynı sonucu verir ve gereksiz git farkı doğmaz.
// Editör kullanır; burada durması birim testinde denenebilmesi içindir.
class DialogLayout {
  public static inline var NODE_WIDTH = 240.;      // düğümün içerik genişliği
  public static inline var NODE_PADDING = 8.;
  public static inline var COLUMN_GAP = 90.;
  public static inline var ROW_GAP = 40.;
  public static inline var BRANCH_GAP = 130.;
  public static inline var COLUMN_STEP = NODE_WIDTH + NODE_PADDING * 2 + COLUMN_GAP;
  public static inline var SHORT_TEXT = 150;
  public static inline var SHORT_CHOICE = 30;
  public static inline var EMPTY_LINE = "Boş satır: tıkla, Inspector'da yaz";

  // Editör yazısı DejaVu Sans Mono 15: eş genişlikli, satır kaydırma karakter sayısıyla bilinir.
  static inline var FONT_SIZE = 15.;
  static inline var CHAR_WIDTH = 9.04;
  static inline var ITEM_SPACING = 4.;
  static inline var MARGIN = 6.;

  public static function columns() : Int {
    return Std.int(NODE_WIDTH / CHAR_WIDTH);
  }

  // Akışa göre sütunlar: başlangıçtan uzaklık sütunu, sıra satırı belirler. Ulaşılmayan düğümler sona.
  public static function arrange(dialog : Dialog) : Map<Int, {x : Float, y : Float}> {
    var placed = new Map<Int, {x : Float, y : Float}>();
    var start = dialog.start();
    if (start == null) return placed;
    var depth = [start.id => 0];
    var order = [start.id];
    var queue = [start.id];
    while (queue.length > 0) {
      var node = dialog.node(queue.shift());
      for (target in targets(node)) {
        if (target <= 0 || dialog.node(target) == null || depth.exists(target)) continue;
        depth.set(target, depth.get(node.id) + 1);
        order.push(target);
        queue.push(target);
      }
    }
    var last = 0;
    for (value in depth) last = Std.int(Math.max(last, value + 1));
    for (node in dialog.nodes) if (!depth.exists(node.id)) {
      depth.set(node.id, last);
      order.push(node.id);
    }
    for (column in 0...last + 1) {
      var y = 0.;
      for (id in order) {
        if (depth.get(id) != column) continue;
        placed.set(id, {x: column * COLUMN_STEP, y: y});
        y += height(dialog.node(id)) + ROW_GAP;
      }
    }
    return placed;
  }

  // Düğümün boyu, editörün çizdiği satırlardan. Biraz fazla tutulur: yerleşimde üst üste binmesin.
  public static function height(node : DialogNode) : Float {
    var line = FONT_SIZE + ITEM_SPACING;
    var rows = line;  // başlık
    switch (node.type) {
      case Dialog.LINE:
        if (!blank(node.speaker)) rows += line;
        var text = blank(node.text) ? EMPTY_LINE : shorten(node.text, SHORT_TEXT);
        rows += wrappedLines(text, columns()) * FONT_SIZE + ITEM_SPACING;
        rows += line;
      case Dialog.CHOICES:
        rows += Math.max(1, node.choices == null ? 0 : node.choices.length) * line;
      case Dialog.CONDITION:
        rows += line * 3;
      case Dialog.START, Dialog.EVENT:
        rows += line * (node.type == Dialog.EVENT ? 2 : 1);
      default:
        rows += line;
    }
    return NODE_PADDING * 2 + rows + 1 + MARGIN;
  }

  // ImGui gibi boşluktan kaydırır; sığmayan uzun kelime bölünür.
  public static function wrappedLines(text : String, columns : Int) : Int {
    var count = 0;
    for (paragraph in text.split("\n")) {
      var width = 0;
      count++;
      for (word in paragraph.split(" ")) {
        var length = word.length;
        if (width > 0 && width + 1 + length > columns) {
          count++;
          width = 0;
        }
        while (length > columns) {
          count++;
          length -= columns;
        }
        width += (width > 0 ? 1 : 0) + length;
      }
    }
    return count;
  }

  public static function targets(node : DialogNode) : Array<Int> {
    var found : Array<Null<Int>> = switch (node.type) {
      case Dialog.CONDITION: [node.yes, node.no];
      case Dialog.CHOICES: node.choices == null ? [] : [for (choice in node.choices) choice.next];
      case Dialog.END: [];
      default: [node.next];
    };
    // Açık türlü dizi: HashLink'te Array<Null<Int>> kutulu değerlerle (ArrayObj) durur, Array<Int> diye dönerse
    // kullanan yerde "Can't cast ArrayObj to ArrayBytes_Int" ile çöker (ajanın get_dialog_lines'ı, 6 Kasım 2026).
    var result : Array<Int> = [];
    for (target in found) result.push(target == null ? 0 : target);
    return result;
  }

  public static function shorten(text : String, limit : Int) {
    return text.length <= limit ? text : text.substr(0, limit - 3) + "...";
  }

  public static inline function blank(text : Null<String>) {
    return text == null || StringTools.trim(text) == "";
  }
}
