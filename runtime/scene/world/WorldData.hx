package scene.world;

import scene.data.SceneFormat;

typedef TerrainLayer = {
  var id : String;
  var title : String;
  var color : Int;
}

// Blender veya 3ds Max'te hazırlanmış arazi. Hücrelere bölünür: her hücre kendi parçasını ve
// yüksekliğini taşır, yeniden içe aktarınca yalnızca değişen hücreler yazılır.
typedef TerrainModel = {
  var source : String;        // FBX, proje köküne göre
  var x : Float;              // dünyadaki merkez
  var y : Float;
  var base : Float;           // modelin en alçak noktasının yüksekliği
  var width : Float;          // X yönündeki genişlik, metre
  var rotation : Float;       // derece
  var heightScale : Float;    // dikey çarpan, 1 oranı korur
  var tiling : Float;         // doku tekrarı
  var originX : Float;        // modelin kendi merkezi, alt noktası ve genişliği
  var originY : Float;
  var originZ : Float;
  var originWidth : Float;
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
  public static inline var SURFACE_SUFFIX = ".terrain.mesh";
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
  public var maxSlope = 42.;                     // yürünebilir en dik eğim, derece
  public var terrainModels : Array<TerrainModel> = [];
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
    if (raw.maxSlope != null) world.maxSlope = raw.maxSlope;
    if (raw.terrainModels != null) world.terrainModels = raw.terrainModels;
    return world;
  }

  public function write() : String {
    var out = new StringBuf();
    out.add('{\n  "version": $VERSION,\n  "columns": $columns,\n  "rows": $rows,');
    out.add('\n  "cellSize": ${SceneFormat.number(cellSize)},\n  "resolution": $resolution,\n  "navResolution": $navResolution,\n  "layers": [');
    var lines = [for (layer in layers) '\n    {"id": "${layer.id}", "title": "${layer.title}", "color": ${layer.color}}'];
    out.add(lines.join(","));
    out.add('\n  ],\n  "maxSlope": ${SceneFormat.number(maxSlope)},\n  "terrainModels": [');
    var models = [for (model in terrainModels) '\n    {"source": "${model.source}", "x": ${n(model.x)}, "y": ${n(model.y)}, "base": ${n(model.base)}, '
      + '"width": ${n(model.width)}, "rotation": ${n(model.rotation)}, "heightScale": ${n(model.heightScale)}, "tiling": ${n(model.tiling)}, '
      + '"originX": ${n(model.originX)}, "originY": ${n(model.originY)}, "originZ": ${n(model.originZ)}, "originWidth": ${n(model.originWidth)}}'];
    out.add(models.join(","));
    out.add(models.length > 0 ? '\n  ]\n}\n' : ']\n}\n');
    return out.toString();
  }

  static function n(value : Float) {
    return SceneFormat.number(value);
  }

  // Diskten yeniden okunan dünyanın düzenlenebilir ayarları.
  public function assignSettings(other : WorldData) {
    maxSlope = other.maxSlope;
    terrainModels = other.terrainModels;
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
