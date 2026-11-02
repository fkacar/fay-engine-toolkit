package scene.world;

import scene.data.SceneFormat;

typedef ScatterItem = {
  var type : String;
  var x : Float;
  var y : Float;
  var rotation : Float;  // derece
  var scale : Float;
}

// Bir hücreye dağıtılmış binlerce küçük nesne. Sahne nesnesi değildir: yükseklik yazılmaz,
// arazi değişince zemini kendiliğinden izler.
class ScatterCell {
  public static inline var VERSION = 1;

  static inline var PRECISION = 100.;

  public var items(default, null) : Array<ScatterItem>;

  public function new(?items : Array<ScatterItem>) {
    this.items = items == null ? [] : items;
  }

  public function clone() {
    return new ScatterCell(items.copy());
  }

  public static function read(text : String) : ScatterCell {
    var raw : Dynamic = haxe.Json.parse(text);
    if (raw.version != VERSION) throw 'Dağıtma sürümü desteklenmiyor: ${raw.version}';
    var groups : Array<Dynamic> = raw.groups;
    var items = [];
    for (group in groups) {
      var rows : Array<Array<Float>> = group.items;
      for (row in rows) items.push({type: (group.type : String), x: row[0], y: row[1], rotation: row[2], scale: row[3]});
    }
    return new ScatterCell(items);
  }

  // Türlere ayrılır ve her tür sıralanır: yerleştirme sırası dosyada fark üretmez.
  public function write() : String {
    var groups = new Map<String, Array<String>>();
    for (item in items) {
      if (!groups.exists(item.type)) groups.set(item.type, []);
      groups.get(item.type).push("[" + [for (value in [item.x, item.y, item.rotation, item.scale]) fixed(value)].join(", ") + "]");
    }
    var types = [for (type in groups.keys()) type];
    types.sort(Reflect.compare);
    var blocks = [];
    for (type in types) {
      var rows = groups.get(type);
      rows.sort(Reflect.compare);
      blocks.push('\n    {"type": "$type", "items": [\n      ' + rows.join(",\n      ") + "\n    ]}");
    }
    return '{\n  "version": $VERSION,\n  "groups": [' + blocks.join(",") + "\n  ]\n}\n";
  }

  static function fixed(value : Float) {
    return SceneFormat.number(Math.round(value * PRECISION) / PRECISION);
  }
}
