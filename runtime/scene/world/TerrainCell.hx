package scene.world;

import scene.data.SceneFormat;

// Bir hücrenin arazisi. Kenar köşeleri komşu hücrede de tutulur, böylece hücre tek başına
// yüklenip çizilebilir. Metin dosyasıdır ve satır satır yazılır: git farkı okunur kalır.
class TerrainCell {
  public static inline var VERSION = 1;

  // Bu kareyi arazi modeli çizer: oyun kendi üçgenini koymaz, fırçalar dokunmaz.
  public static inline var COVERED = 35;

  static inline var PAINT_DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz";
  static inline var HEIGHT_PRECISION = 100.;

  public var resolution(default, null) : Int;
  public var heights(default, null) : Array<Float>;  // (resolution + 1) kare, satır satır
  public var paint(default, null) : Array<Int>;      // kare başına katman

  public function new(resolution : Int, heights : Array<Float>, paint : Array<Int>) {
    this.resolution = resolution;
    this.heights = heights;
    this.paint = paint;
  }

  public static function flat(resolution : Int, height = 0.) {
    var corners = (resolution + 1) * (resolution + 1);
    return new TerrainCell(resolution, [for (i in 0...corners) height], [for (i in 0...resolution * resolution) 0]);
  }

  public function hasCoverage() {
    return paint.indexOf(COVERED) >= 0;
  }

  // Aynı alanı başka sayıda kareyle örnekler: yükseklik doğrusal, boya en yakın kareden.
  public function resample(target : Int) : TerrainCell {
    if (target == resolution) return clone();
    var result = TerrainCell.flat(target);
    var ratio = resolution / target;
    for (y in 0...target + 1)
      for (x in 0...target + 1) {
        var sx = x * ratio, sy = y * ratio;
        var ix = Std.int(Math.min(sx, resolution - 1)), iy = Std.int(Math.min(sy, resolution - 1));
        var fx = sx - ix, fy = sy - iy;
        var bottom = height(ix, iy) * (1 - fx) + height(ix + 1, iy) * fx;
        var top = height(ix, iy + 1) * (1 - fx) + height(ix + 1, iy + 1) * fx;
        result.setHeight(x, y, bottom * (1 - fy) + top * fy);
      }
    for (y in 0...target)
      for (x in 0...target)
        result.setLayer(x, y, layer(Std.int((x + 0.5) * ratio), Std.int((y + 0.5) * ratio)));
    return result;
  }

  public function clone() {
    return new TerrainCell(resolution, heights.copy(), paint.copy());
  }

  public inline function height(x : Int, y : Int) {
    return heights[y * (resolution + 1) + x];
  }

  public inline function setHeight(x : Int, y : Int, value : Float) {
    heights[y * (resolution + 1) + x] = value;
  }

  public inline function layer(x : Int, y : Int) {
    return paint[y * resolution + x];
  }

  public inline function setLayer(x : Int, y : Int, value : Int) {
    paint[y * resolution + x] = value;
  }

  public static function read(text : String) : TerrainCell {
    var raw : Dynamic = haxe.Json.parse(text);
    if (raw.version != VERSION) throw 'Arazi sürümü desteklenmiyor: ${raw.version}';
    var rows : Array<Array<Float>> = raw.heights;
    var heights = [];
    for (row in rows) for (value in row) heights.push((value : Float));
    var lines : Array<String> = raw.paint;
    var paint = [];
    for (line in lines) for (i in 0...line.length) paint.push(PAINT_DIGITS.indexOf(line.charAt(i)));
    return new TerrainCell(rows.length - 1, heights, paint);
  }

  public function write() : String {
    var out = new StringBuf();
    out.add('{\n  "version": $VERSION,\n  "heights": [');
    var size = resolution + 1;
    var rows = [for (y in 0...size) '\n    [' + [for (x in 0...size) SceneFormat.number(Math.round(height(x, y) * HEIGHT_PRECISION) / HEIGHT_PRECISION)].join(", ") + "]"];
    out.add(rows.join(","));
    out.add('\n  ],\n  "paint": [');
    var lines = [for (y in 0...resolution) '\n    "' + [for (x in 0...resolution) PAINT_DIGITS.charAt(layer(x, y))].join("") + '"'];
    out.add(lines.join(","));
    out.add('\n  ]\n}\n');
    return out.toString();
  }
}
