package scene.world;

import scene.data.SceneFormat;

typedef TerrainLayer = {
  var id : String;
  var title : String;
  var color : Int;
}

// Dünyanın ızgarası. Hücrelerin içeriği ayrı dosyalardadır: iki kişi farklı hücrelerde
// çalışınca aynı dosyaya dokunmaz, oyun da yalnızca yakındaki hücreleri yükler.
class WorldData {
  public static inline var VERSION = 1;
  public static inline var SUFFIX = ".world.json";
  public static inline var OBJECTS_SUFFIX = ".scene.json";
  public static inline var TERRAIN_SUFFIX = ".terrain.json";
  public static inline var SCATTER_SUFFIX = ".scatter.json";
  public static inline var NAV_SUFFIX = ".nav.json";
  // Hücreye bağlı olmayan nesneler, oyuncunun ekibi gibi. Her zaman yüklüdür.
  public static inline var GLOBAL = -1;
  public static inline var OUTSIDE = -2;

  static inline var GLOBAL_FILE = "global.scene.json";
  static inline var ENVIRONMENT_FILE = "environment.json";

  public var directory(default, null) : String;  // `res` köküne göre
  public var columns(default, null) : Int;
  public var rows(default, null) : Int;
  public var cellSize(default, null) : Float;
  public var resolution(default, null) : Int;    // hücre kenarındaki arazi karesi sayısı
  public var layers(default, null) : Array<TerrainLayer>;
  public var navResolution = 90;                 // hücre kenarındaki yol ağı düğümü sayısı
  public var width(get, never) : Float;
  public var height(get, never) : Float;
  public var left(get, never) : Float;
  public var bottom(get, never) : Float;
  public var step(get, never) : Float;           // arazi karesinin kenarı

  public function new(directory : String, columns : Int, rows : Int, cellSize : Float, resolution : Int, layers : Array<TerrainLayer>) {
    this.directory = directory;
    this.columns = columns;
    this.rows = rows;
    this.cellSize = cellSize;
    this.resolution = resolution;
    this.layers = layers;
  }

  public static function isWorldFile(path : String) {
    return StringTools.endsWith(path, SUFFIX);
  }

  public static function read(text : String, directory : String) : WorldData {
    var raw : Dynamic = haxe.Json.parse(text);
    if (raw.version != VERSION) throw 'Dünya sürümü desteklenmiyor: ${raw.version}';
    var layers : Array<TerrainLayer> = raw.layers;
    var world = new WorldData(directory, raw.columns, raw.rows, raw.cellSize, raw.resolution, layers);
    if (raw.navResolution != null) world.navResolution = raw.navResolution;
    return world;
  }

  public function write() : String {
    var out = new StringBuf();
    out.add('{\n  "version": $VERSION,\n  "columns": $columns,\n  "rows": $rows,');
    out.add('\n  "cellSize": ${SceneFormat.number(cellSize)},\n  "resolution": $resolution,\n  "navResolution": $navResolution,\n  "layers": [');
    var lines = [for (layer in layers) '\n    {"id": "${layer.id}", "title": "${layer.title}", "color": ${layer.color}}'];
    out.add(lines.join(","));
    out.add('\n  ]\n}\n');
    return out.toString();
  }

  public function cellAt(x : Float, y : Float) : Int {
    var column = Math.floor((x - left) / cellSize), row = Math.floor((y - bottom) / cellSize);
    if (column < 0 || row < 0 || column >= columns || row >= rows) return OUTSIDE;
    return id(column, row);
  }

  // Dünya dışına taşan nesne en yakın hücrede kalır.
  public function nearest(x : Float, y : Float) : Int {
    var column = Math.floor((x - left) / cellSize), row = Math.floor((y - bottom) / cellSize);
    return id(Std.int(Math.max(0, Math.min(column, columns - 1))), Std.int(Math.max(0, Math.min(row, rows - 1))));
  }

  public inline function id(column : Int, row : Int) {
    return row * columns + column;
  }

  public inline function columnOf(cell : Int) {
    return cell % columns;
  }

  public inline function rowOf(cell : Int) {
    return Std.int(cell / columns);
  }

  public function cellLeft(cell : Int) {
    return left + columnOf(cell) * cellSize;
  }

  public function cellBottom(cell : Int) {
    return bottom + rowOf(cell) * cellSize;
  }

  public function cells() : Array<Int> {
    return [for (cell in 0...columns * rows) cell];
  }

  // Merkezden en çok `radius` hücre uzaktakiler, yakından uzağa.
  public function around(center : Int, radius : Int) : Array<Int> {
    var column = columnOf(center), row = rowOf(center);
    var found = [];
    for (y in row - radius...row + radius + 1)
      for (x in column - radius...column + radius + 1)
        if (x >= 0 && y >= 0 && x < columns && y < rows) found.push(id(x, y));
    function distance(cell : Int) {
      return Math.max(Math.abs(columnOf(cell) - column), Math.abs(rowOf(cell) - row));
    }
    found.sort((a, b) -> distance(a) == distance(b) ? a - b : Reflect.compare(distance(a), distance(b)));
    return found;
  }

  public function path(cell : Int, suffix : String) {
    if (cell == GLOBAL) return '$directory/$GLOBAL_FILE';
    return '$directory/c_${columnOf(cell)}_${rowOf(cell)}$suffix';
  }

  public function environmentPath() {
    return '$directory/$ENVIRONMENT_FILE';
  }

  public function title(cell : Int) {
    return cell == GLOBAL ? "Genel" : 'Hücre ${columnOf(cell)},${rowOf(cell)}';
  }

  function get_width() {
    return columns * cellSize;
  }

  function get_height() {
    return rows * cellSize;
  }

  function get_left() {
    return -width * 0.5;
  }

  function get_bottom() {
    return -height * 0.5;
  }

  function get_step() {
    return cellSize / resolution;
  }
}
