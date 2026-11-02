package scene.data;

import haxe.DynamicAccess;
import scene.data.SceneData;
import scene.story.Dialog;

typedef MergeOutcome = {
  var text : Null<String>;          // null: çakışma var ve taraf seçilmedi
  var conflicts : Array<String>;    // çakışan birimlerin adları
}

private typedef Unit<T> = {key : String, text : String, value : T};

// Üç yönlü birleştirme: taban (editörün diskten son okuduğu), editördeki hal ve diskteki yeni hal.
// Dosya editör açıkken dışarıda (git pull, metin editörü, LLM ajanı) değiştiyse kaydetmek
// dışarıdaki işi silmesin diye kullanılır. Birim, sahnede nesne, tabloda satır, diyalogda
// düğümdür: yalnızca bir tarafın değiştirdiği birim o tarafın haliyle kalır. İki taraf aynı
// birimi farklı değiştirdiyse çakışmadır; `prefer` verilirse çakışmada o taraf kazanır.
class ThreeWay {
  public static inline var MINE = "benim";
  public static inline var THEIRS = "disk";

  public static function scene(base : Null<String>, mine : Null<String>, theirs : Null<String>, ?prefer : String) : MergeOutcome {
    if (mine == null || theirs == null) return whole(base, mine, theirs, prefer, "dosya");
    function units(text : Null<String>) : Array<Unit<EntityData>> {
      if (text == null) return [];
      var data = SceneFormat.read(text);
      return [for (entity in data.entities) {key: entity.id, text: entityText(entity), value: entity}];
    }
    var merged = keyed(units(base), units(mine), units(theirs), prefer, unit -> unit.value.name);
    if (merged.conflicts.length > 0 && prefer == null) return {text: null, conflicts: merged.conflicts};
    var data = new SceneData(SceneFormat.VERSION);
    for (unit in merged.items) data.entities.push(unit.value);
    return {text: SceneFormat.write(data), conflicts: merged.conflicts};
  }

  public static function table(name : String, base : Null<String>, mine : Null<String>, theirs : Null<String>, ?prefer : String) : MergeOutcome {
    if (mine == null || theirs == null) return whole(base, mine, theirs, prefer, name);
    var b = base == null ? null : DataTable.read(name, base), m = DataTable.read(name, mine), t = DataTable.read(name, theirs);
    function header(table : Null<DataTable>) {
      if (table == null) return null;
      var copy = new DataTable(name, table.title);
      copy.columns = table.columns;
      return copy.write();
    }
    function units(table : Null<DataTable>) : Array<Unit<DynamicAccess<Dynamic>>> {
      return table == null ? [] : [for (row in table.rows) {key: Std.string(row.get("id")), text: canonical(row), value: row}];
    }
    var conflicts = [];
    var head = pick(header(b), header(m), header(t), prefer);
    if (head.conflict) conflicts.push('$name sütunları');
    var rows = keyed(units(b), units(m), units(t), prefer, unit -> unit.key);
    conflicts = conflicts.concat(rows.conflicts);
    if (conflicts.length > 0 && prefer == null) return {text: null, conflicts: conflicts};
    var chosen = head.value == header(t) ? t : m;
    var result = new DataTable(name, chosen.title);
    result.columns = chosen.columns;
    result.rows = [for (unit in rows.items) unit.value];
    return {text: result.write(), conflicts: conflicts};
  }

  public static function dialog(id : String, base : Null<String>, mine : Null<String>, theirs : Null<String>, ?prefer : String) : MergeOutcome {
    if (mine == null || theirs == null) return whole(base, mine, theirs, prefer, id);
    var b = base == null ? null : Dialog.read(id, base), m = Dialog.read(id, mine), t = Dialog.read(id, theirs);
    function units(dialog : Null<Dialog>) : Array<Unit<DialogNode>> {
      return dialog == null ? [] : [for (node in dialog.nodes) {key: Std.string(node.id), text: canonical(node), value: node}];
    }
    var conflicts = [];
    var title = pick(b == null ? null : b.title, m.title, t.title, prefer);
    if (title.conflict) conflicts.push('$id başlığı');
    var nodes = keyed(units(b), units(m), units(t), prefer, unit -> '${m.title} düğüm ${unit.key}');
    conflicts = conflicts.concat(nodes.conflicts);
    if (conflicts.length > 0 && prefer == null) return {text: null, conflicts: conflicts};
    var result = new Dialog(id, title.value);
    result.nodes = [for (unit in nodes.items) unit.value];
    return {text: result.write(), conflicts: conflicts};
  }

  // Birimlere bölünmeyen dosyalar (arazi, dağıtma, ortam) ve silinen dosyalar bütün olarak karşılaştırılır.
  public static function whole(base : Null<String>, mine : Null<String>, theirs : Null<String>, ?prefer : String, label = "dosya") : MergeOutcome {
    var result = pick(base, mine, theirs, prefer);
    if (result.conflict && prefer == null) return {text: null, conflicts: [label]};
    return {text: result.value, conflicts: result.conflict ? [label] : []};
  }

  static function pick(base : Null<String>, mine : Null<String>, theirs : Null<String>, prefer : Null<String>) : {value : Null<String>, conflict : Bool} {
    if (mine == theirs) return {value: mine, conflict: false};
    if (mine == base) return {value: theirs, conflict: false};
    if (theirs == base) return {value: mine, conflict: false};
    return {value: prefer == THEIRS ? theirs : mine, conflict: true};
  }

  static function keyed<T>(base : Array<Unit<T>>, mine : Array<Unit<T>>, theirs : Array<Unit<T>>, prefer : Null<String>,
      name : Unit<T>->String) : {items : Array<Unit<T>>, conflicts : Array<String>} {
    var b = index(base), m = index(mine), t = index(theirs);
    var chosen = new Map<String, Unit<T>>();
    var conflicts = [];
    var keys = order(mine, theirs, base);
    for (key in keys) {
      var bu = b.get(key), mu = m.get(key), tu = t.get(key);
      var result = pick(bu == null ? null : bu.text, mu == null ? null : mu.text, tu == null ? null : tu.text, prefer);
      if (result.conflict) conflicts.push(name(mu != null ? mu : tu));
      var unit = result.value == null ? null : result.value == (mu == null ? null : mu.text) ? mu : tu;
      if (unit != null) chosen.set(key, unit);
    }
    return {items: [for (key in keys) if (chosen.exists(key)) chosen.get(key)], conflicts: conflicts};
  }

  // Editördeki sıra korunur; diskte eklenen birim diskteki öncülünün arkasına girer.
  static function order<T>(mine : Array<Unit<T>>, theirs : Array<Unit<T>>, base : Array<Unit<T>>) : Array<String> {
    var keys = [for (unit in mine) unit.key];
    var previous : Null<String> = null;
    for (unit in theirs) {
      if (keys.indexOf(unit.key) < 0) keys.insert(previous == null ? 0 : keys.indexOf(previous) + 1, unit.key);
      previous = unit.key;
    }
    // Bir tarafın sildiği, öbürünün değiştirdiği birim çakışmadır: tabandan da bakılır.
    for (unit in base) if (keys.indexOf(unit.key) < 0) keys.push(unit.key);
    return keys;
  }

  static function index<T>(units : Array<Unit<T>>) : Map<String, Unit<T>> {
    return [for (unit in units) unit.key => unit];
  }

  static function entityText(entity : EntityData) : String {
    var data = new SceneData(SceneFormat.VERSION);
    data.entities.push(entity);
    return SceneFormat.write(data);
  }

  // Alan sırasından bağımsız metin: aynı içerik her zaman aynı metni verir.
  static function canonical(value : Dynamic) : String {
    if (value == null || !Reflect.isObject(value) || Std.isOfType(value, String)) return haxe.Json.stringify(value);
    if (Std.isOfType(value, Array)) {
      var items : Array<Dynamic> = value;
      return "[" + [for (item in items) canonical(item)].join(",") + "]";
    }
    var fields = Reflect.fields(value);
    fields.sort(Reflect.compare);
    return "{" + [for (field in fields) haxe.Json.stringify(field) + ":" + canonical(Reflect.field(value, field))].join(",") + "}";
  }
}
