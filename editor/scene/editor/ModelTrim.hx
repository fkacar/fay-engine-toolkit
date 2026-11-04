package scene.editor;

import hxd.fmt.hmd.Data;

import scene.editor.ImportSettings.TrimBox;

// Yapay zekâ modellerindeki fazlalık için içe aktarma ayarı: kutuların içinde kalan üçgenler atılır
// (kuyruğun altındaki yer plakası, havada kalan parça). Ayar kaynağın yanında <ad>.aktarim.json
// dosyasındadır (ImportSettings), FBX'e dokunulmaz. Koordinatlar modelin kendi birimleriyle ve Heaps'in eksenleriyle
// (Z yukarı); sınırlar ve taban haritası aynı birimde verilir. Üçgenin ağırlık merkezi kutudaysa atılır.
class ModelTrim {
  static inline var MAP_COLUMNS = 32;
  static inline var FLOOR_FRACTION = 0.03;

  public static function settingsPath(source : String) : String {
    return ImportSettings.path(source);
  }

  public static function read(source : String) : Array<TrimBox> {
    return ImportSettings.read(source).trim;
  }

  // Kutu yoksa ayar dosyası silinmez, boş listeyle yazılır: sonraki içe aktarma da kırpmasız olur.
  // Dosyadaki öteki ayarlar (klipler) korunur.
  public static function write(source : String, boxes : Array<TrimBox>) {
    var settings = ImportSettings.read(source);
    settings.trim = boxes;
    settings.write(source);
  }

  public static function check(box : Dynamic) : TrimBox {
    return ImportSettings.checkBox(box);
  }

  // Üçgen silinmez, üç köşesi aynı noktaya alınır: çizilmez, köşe ve deri verisi bozulmaz.
  public static function apply(hmd : Data, boxes : Array<TrimBox>) : Int {
    if (boxes.length == 0) return 0;
    var removed = 0;
    eachTriangle(hmd, (a, b, c, at) -> {
      var x = (a[0] + b[0] + c[0]) / 3, y = (a[1] + b[1] + c[1]) / 3, z = (a[2] + b[2] + c[2]) / 3;
      for (box in boxes)
        if (x >= box.min[0] && x <= box.max[0] && y >= box.min[1] && y <= box.max[1] && z >= box.min[2] && z <= box.max[2]) {
          at.collapse();
          removed++;
          break;
        }
    });
    return removed;
  }

  public static function bounds(hmd : Data) : {min : Array<Float>, max : Array<Float>} {
    var min = [1e30, 1e30, 1e30], max = [-1e30, -1e30, -1e30];
    for (geometry in hmd.geometries) {
      var b = geometry.bounds;
      min = [Math.min(min[0], b.xMin), Math.min(min[1], b.yMin), Math.min(min[2], b.zMin)];
      max = [Math.max(max[0], b.xMax), Math.max(max[1], b.yMax), Math.max(max[2], b.zMax)];
    }
    return {min: [for (v in min) round(v)], max: [for (v in max) round(v)]};
  }

  // Ajan için tabandan bakış: alt %3'te ağırlık merkezi olan üçgenlerin x, y ızgarasındaki sayısı.
  // Ayaklar iki küme olur; başka bir küme genellikle fazlalıktır.
  public static function floorMap(hmd : Data, ?fraction : Float) : Dynamic {
    var box = bounds(hmd);
    var height = box.max[2] - box.min[2];
    var limit = box.min[2] + height * (fraction == null ? FLOOR_FRACTION : fraction);
    var width = box.max[0] - box.min[0], depth = box.max[1] - box.min[1];
    var cell = Math.max(width, depth) / MAP_COLUMNS;
    var columns = Std.int(Math.ceil(width / cell)), rows = Std.int(Math.ceil(depth / cell));
    var counts = [for (r in 0...rows) [for (c in 0...columns) 0]];
    eachTriangle(hmd, (a, b, c, _) -> {
      var z = (a[2] + b[2] + c[2]) / 3;
      if (z > limit) return;
      var x = (a[0] + b[0] + c[0]) / 3, y = (a[1] + b[1] + c[1]) / 3;
      var column = Std.int(Math.min(columns - 1, (x - box.min[0]) / cell));
      var row = Std.int(Math.min(rows - 1, (box.max[1] - y) / cell));
      counts[row][column]++;
    });
    var lines = [for (row in counts) [for (count in row) count == 0 ? "." : count < 10 ? Std.string(count) : "#"].join("")];
    return {
      floorHeight: round(limit),
      cellSize: round(cell),
      origin: "ilk satır y=" + round(box.max[1]) + ", ilk sütun x=" + round(box.min[0]) + "; satırlar aşağı doğru y azalır, sütunlar sağa doğru x artar",
      legend: ". yok, 1-9 üçgen sayısı, # 10 ve üstü",
      map: lines,
    };
  }

  static function eachTriangle(hmd : Data, visit : (Array<Float>, Array<Float>, Array<Float>, {collapse : Void->Void}) -> Void) {
    var bytes = hmd.data;
    for (geometry in hmd.geometries) {
      var position = geometry.vertexFormat.getInput("position");
      if (position == null || position.precision != F32) continue;
      var offset = geometry.vertexFormat.calculateInputOffset("position");
      var stride = geometry.vertexFormat.strideBytes;
      var small = geometry.vertexCount <= 0x10000;
      var size = small ? 2 : 4;
      inline function index(i : Int) return small ? bytes.getUInt16(geometry.indexPosition + i * 2) : bytes.getInt32(geometry.indexPosition + i * 4);
      function vertex(v : Int) {
        var at = geometry.vertexPosition + v * stride + offset;
        return [bytes.getFloat(at), bytes.getFloat(at + 4), bytes.getFloat(at + 8)];
      }
      var t = 0;
      while (t + 2 < geometry.indexCount) {
        var i0 = index(t), i1 = index(t + 1), i2 = index(t + 2), first = t;
        // Kırpılmış üçgen tek noktadır: sayılmaz, yeniden kırpılmaz.
        if (i0 == i1 && i1 == i2) {
          t += 3;
          continue;
        }
        visit(vertex(i0), vertex(i1), vertex(i2), {collapse: () -> {
          for (k in 1...3) {
            if (small) bytes.setUInt16(geometry.indexPosition + (first + k) * size, i0);
            else bytes.setInt32(geometry.indexPosition + (first + k) * size, i0);
          }
        }});
        t += 3;
      }
    }
  }

  static function round(value : Float) : Float {
    return Math.round(value * 100) / 100;
  }
}
