package scene.story;

typedef DialogChoice = {
  var text : String;
  var next : Int;
}

typedef DialogNode = {
  var id : Int;
  var type : String;
  var x : Float;
  var y : Float;
  @:optional var speaker : String;
  @:optional var text : String;
  @:optional var next : Int;                     // 0 ise yok
  @:optional var choices : Array<DialogChoice>;
  @:optional var kind : String;                  // koşul: değişken veya eşya
  @:optional var name : String;
  @:optional var value : Int;
  @:optional var yes : Int;
  @:optional var no : Int;
  @:optional var event : String;
}

// Konuşma ağacı. Olay düğümü adlı bir olay yayar, aynı olayı bekleyen tetikleyicinin eylemleri
// çalışır: eşya verme gibi işler tek yerde yazılır. Her düğüm tek satıra yazılır.
class Dialog {
  public static inline var VERSION = 1;
  public static inline var DIRECTORY = "data/dialogs";
  public static inline var SUFFIX = ".dialog.json";
  public static inline var START = "baslangic";
  public static inline var LINE = "satir";
  public static inline var CHOICES = "secenek";
  public static inline var CONDITION = "kosul";
  public static inline var EVENT = "olay";
  public static inline var END = "bitis";
  public static inline var FLAG = "degisken";
  public static inline var ITEM = "esya";

  public var id(default, null) : String;
  public var title : String;
  public var nodes : Array<DialogNode> = [];

  public function new(id : String, title : String) {
    this.id = id;
    this.title = title;
  }

  public static function create(id : String, title : String) {
    var dialog = new Dialog(id, title);
    dialog.nodes.push({id: 1, type: START, x: 0, y: 0, next: 2});
    dialog.nodes.push({id: 2, type: LINE, x: 220, y: 0, speaker: "", text: "", next: 3});
    dialog.nodes.push({id: 3, type: END, x: 560, y: 0});
    return dialog;
  }

  public static function read(id : String, text : String) : Dialog {
    var raw : Dynamic = haxe.Json.parse(text);
    if (raw.version != VERSION) throw '$id diyaloğunun sürümü desteklenmiyor: ${raw.version}';
    var dialog = new Dialog(id, raw.title);
    var nodes : Array<DialogNode> = raw.nodes;
    dialog.nodes = nodes;
    return dialog;
  }

  public function write() : String {
    var sorted = nodes.copy();
    sorted.sort((a, b) -> a.id - b.id);
    var lines = [for (node in sorted) '\n    ' + nodeText(node)];
    return '{\n  "version": $VERSION,\n  "title": ${haxe.Json.stringify(title)},\n  "nodes": [' + lines.join(",") + "\n  ]\n}\n";
  }

  public function clone() {
    return read(id, write());
  }

  public function node(id : Int) : Null<DialogNode> {
    for (item in nodes) if (item.id == id) return item;
    return null;
  }

  public function start() : Null<DialogNode> {
    for (item in nodes) if (item.type == START) return item;
    return null;
  }

  public function freeId() {
    var id = 1;
    for (item in nodes) if (item.id >= id) id = item.id + 1;
    return id;
  }

  // Silinen düğüme giden bağlantılar da kalkar.
  public function remove(id : Int) {
    nodes = nodes.filter(item -> item.id != id);
    for (item in nodes) {
      if (item.next == id) item.next = 0;
      if (item.yes == id) item.yes = 0;
      if (item.no == id) item.no = 0;
      if (item.choices != null) for (choice in item.choices) if (choice.next == id) choice.next = 0;
    }
  }

  static function nodeText(node : DialogNode) {
    var parts = ['"id": ${node.id}', '"type": ${q(node.type)}', '"x": ${Math.round(node.x)}', '"y": ${Math.round(node.y)}'];
    for (key in ["speaker", "text", "kind", "name", "event"]) {
      var value : Null<String> = Reflect.field(node, key);
      if (value != null) parts.push('"$key": ${q(value)}');
    }
    for (key in ["value", "next", "yes", "no"]) {
      var value : Null<Int> = Reflect.field(node, key);
      if (value != null) parts.push('"$key": $value');
    }
    if (node.choices != null)
      parts.push('"choices": [' + [for (choice in node.choices) '{"text": ${q(choice.text)}, "next": ${choice.next}}'].join(", ") + "]");
    return "{" + parts.join(", ") + "}";
  }

  static function q(text : String) {
    return haxe.Json.stringify(text);
  }
}
