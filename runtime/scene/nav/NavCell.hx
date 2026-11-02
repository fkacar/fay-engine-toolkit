package scene.nav;

import haxe.io.Bytes;

typedef NavShape = {
  var x : Float;
  var y : Float;
  var halfX : Float;   // yuvarlak şekilde yarıçap
  var halfY : Float;
  var angle : Float;   // radyan
  var isRound : Bool;
  @:optional var points : Array<Float>;  // çokgen: x, y sırasıyla
}

// Bir hücrenin yol ızgarası. Satırlar sıra sıra uzunluklardır (yürünür, kapalı, yürünür...):
// çoğu satır kısa kalır, değişmeyen satır git farkı üretmez.
class NavCell {
  public static inline var VERSION = 1;

  public var size(default, null) : Int;

  var blocked : Bytes;

  public function new(size : Int) {
    this.size = size;
    blocked = Bytes.alloc(size * size);
    blocked.fill(0, size * size, 0);
  }

  public inline function isBlocked(x : Int, y : Int) {
    return blocked.get(y * size + x) != 0;
  }

  public inline function block(x : Int, y : Int) {
    blocked.set(y * size + x, 1);
  }

  public static function read(text : String) : NavCell {
    var raw : Dynamic = haxe.Json.parse(text);
    if (raw.version != VERSION) throw 'Yol ağı sürümü desteklenmiyor: ${raw.version}';
    var rows : Array<String> = raw.rows;
    var cell = new NavCell(rows.length);
    for (y in 0...rows.length) {
      var x = 0, closed = false;
      for (run in rows[y].split(",")) {
        var length = Std.parseInt(run);
        if (closed) for (i in x...x + length) cell.block(i, y);
        x += length;
        closed = !closed;
      }
    }
    return cell;
  }

  public function write() : String {
    var rows = [for (y in 0...size) '\n    "${writeRow(y)}"'];
    return '{\n  "version": $VERSION,\n  "rows": [' + rows.join(",") + "\n  ]\n}\n";
  }

  function writeRow(y : Int) {
    var runs = [];
    var closed = false, length = 0;
    for (x in 0...size) {
      if (isBlocked(x, y) != closed) {
        runs.push(length);
        length = 0;
        closed = !closed;
      }
      length++;
    }
    runs.push(length);
    return runs.join(",");
  }
}
