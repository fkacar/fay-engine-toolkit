package scene.editor;

import scene.Entity;
import scene.SceneInstance;
import scene.data.SceneFormat;
import scene.nav.NavBaker;
import scene.nav.NavShapes;
import scene.nav.NavWorld;
import scene.world.ScatterCell;
import scene.world.WorldData;
import scene.world.WorldState;
import sys.FileSystem;
import sys.io.File;

// Editörde açık dünya. Arazi her zaman görünür, nesneler ve dağıtılanlar hücre hücre yüklenir.
// Kayıtta yalnızca değişen dosyalar yazılır: başkasının hücresine git farkı düşmez.
class WorldDocument {
  static inline var ROOT = "res/";
  static inline var DEFAULT_RADIUS = 1;
  static inline var BOUNDS_REACH = 700.;
  static inline var NAV_REACH = 60.;
  static inline var NAV_LIFT = 0.2;
  static inline var NAV_COLOR = 0xE0FF4040;
  static inline var LOADED_COLOR = 0xC060C0F0;
  static inline var UNLOADED_COLOR = 0x60A0A0A0;

  public var state(default, null) : WorldState;
  public var data(get, never) : WorldData;
  public var brush(default, null) : WorldBrush;
  public var showBounds = true;
  public var showNav = false;

  var editor : Editor;
  var navView : NavWorld;
  var touchedEnvironment = false;
  var scene : SceneInstance;
  var loaded = new Map<Int, Bool>();
  var disk = new Map<String, Null<String>>();
  var dirty = new Map<Int, Bool>();
  var dirtyRevision = -1;
  var touchedTerrain = new Map<Int, Bool>();
  var touchedScatter = new Map<Int, Bool>();
  var recovered : Null<Map<String, String>>;

  public function new(editor : Editor, scene : SceneInstance, state : WorldState) {
    this.editor = editor;
    this.scene = scene;
    this.state = state;
    state.read = readFile;
    brush = new WorldBrush(state, isLoaded, strokeChanged);
    navView = new NavWorld(state);
  }

  public function open(cells : Array<Int>) {
    disk = new Map();
    touchedTerrain = new Map();
    touchedScatter = new Map();
    for (cell in [for (key in loaded.keys()) key]) state.unloadScatter(cell);
    loaded = new Map();
    touchedEnvironment = false;
    state.loadAllTerrain();
    state.reloadEnvironment();
    scene.load(state.objects(WorldData.GLOBAL));
    for (entity in scene.entities) if (entity.parent == null) entity.cell = WorldData.GLOBAL;
    var start = cells.length > 0 ? cells : data.around(data.nearest(0, 0), DEFAULT_RADIUS);
    for (cell in start) loadCell(cell);
  }

  public function close() {
    for (cell in [for (key in loaded.keys()) key]) state.unloadScatter(cell);
    loaded = new Map();
    state.loadAllTerrain();
  }

  public function isLoaded(cell : Int) {
    return loaded.exists(cell);
  }

  public function loadedCells() : Array<Int> {
    var cells = [for (cell in loaded.keys()) cell];
    cells.sort(Reflect.compare);
    return cells;
  }

  public function isComplete() {
    return loadedCells().length == data.columns * data.rows;
  }

  public function load(cell : Int) {
    if (isLoaded(cell)) return;
    loadCell(cell);
    editor.document.cellsChanged();
  }

  // Hücre kaydedilmiş sayılır: değişiklikleri varsa kayıt sorusu arayüzde sorulur.
  public function unload(cell : Int) {
    if (!isLoaded(cell)) return;
    editor.commands.forget(command -> {
      if (Std.isOfType(command, CellCommand) && cast(command, CellCommand).touchesCell(cell)) return true;
      return Lambda.exists(command.touched(), entity -> cellOf(entity.root) == cell);
    });
    for (root in rootsIn(cell)) scene.destroyEntity(root);
    state.unloadScatter(cell);
    loaded.remove(cell);
    if (touchedTerrain.exists(cell)) state.loadTerrain(cell);
    touchedTerrain.remove(cell);
    touchedScatter.remove(cell);
    dirtyRevision = -1;
    editor.document.cellsChanged();
  }

  // Kök nesnenin bulunduğu yer belirler: başka hücreye taşınan nesne kayıtta oraya geçer.
  public function cellOf(root : Entity) : Int {
    return root.cell == WorldData.GLOBAL ? WorldData.GLOBAL : data.nearest(root.x, root.y);
  }

  public function rootsIn(cell : Int) : Array<Entity> {
    return scene.entities.filter(entity -> entity.parent == null && cellOf(entity) == cell);
  }

  public function isDirty(cell : Int) {
    if (dirtyRevision != editor.commands.revision) {
      dirtyRevision = editor.commands.revision;
      dirty = new Map();
      var changed = changedFiles();
      for (candidate in [WorldData.GLOBAL].concat(data.cells()))
        for (suffix in [WorldData.OBJECTS_SUFFIX, WorldData.TERRAIN_SUFFIX, WorldData.SCATTER_SUFFIX])
          if (changed.exists(data.path(candidate, suffix))) dirty.set(candidate, true);
    }
    return dirty.exists(cell);
  }

  public function save() {
    // Yüklü olmayan hücreye taşınan nesne o hücrenin dosyasına yazılabilsin.
    for (root in scene.entities.filter(entity -> entity.parent == null)) {
      var cell = cellOf(root);
      if (cell != WorldData.GLOBAL && !isLoaded(cell)) loadCell(cell);
    }
    var files = changedFiles();
    // Değişen hücrenin yol ağı kayıtla birlikte yenilenir, eski kalması unutulmaz.
    var baked = [for (cell in loadedCells()) if (hasChanged(files, cell)) cell];
    for (path => text in navFiles(baked)) if (diskText(path) != text) files.set(path, text);
    write(files);
    for (root in scene.entities) if (root.parent == null && root.cell != WorldData.GLOBAL) root.cell = cellOf(root);
    touchedTerrain = new Map();
    touchedScatter = new Map();
    touchedEnvironment = false;
    recovered = null;
    dirtyRevision = -1;
    return Lambda.count(files);
  }

  // Elle hesaplama: prefab değişince veya komşu hücrenin engeli eklenince gerekir.
  public function bakeLoaded() {
    var files = new Map<String, String>();
    for (path => text in navFiles(loadedCells())) if (diskText(path) != text) files.set(path, text);
    write(files);
    return Lambda.count(files);
  }

  public function environmentEdited() {
    touchedEnvironment = true;
    dirtyRevision = -1;
  }

  public function isEnvironmentDirty() {
    return touchedEnvironment && state.environment.write() != diskText(data.environmentPath());
  }

  public function autosave(directory : String) {
    if (!FileSystem.exists(directory)) FileSystem.createDirectory(directory);
    for (path => text in changedFiles()) File.saveContent(directory + "/" + haxe.io.Path.withoutDirectory(path), text);
  }

  public function recover(directory : String, cells : Array<Int>) {
    recovered = new Map();
    for (name in FileSystem.readDirectory(directory)) recovered.set(name, File.getContent('$directory/$name'));
    open(cells);
  }

  // Fırçadan sonra zemine oturan nesneler yeni yüksekliğe geçer.
  function strokeChanged(terrain : Array<Int>, scatter : Array<Int>) {
    for (cell in scatter) touchedScatter.set(cell, true);
    for (cell in terrain) touchedTerrain.set(cell, true);
    dirtyRevision = -1;
    if (terrain.length == 0) return;
    for (entity in scene.entities) {
      if (terrain.indexOf(data.nearest(entity.root.x, entity.root.y)) < 0) continue;
      for (component in entity.components) component.onEntityMoved();
    }
    for (cell in terrain) if (state.scatter.exists(cell)) state.view.scatterChanged(cell);
  }

  public function drawBounds(overlay : scene.Overlay, focusX : Float, focusY : Float) {
    if (!showBounds) return;
    for (cell in data.cells()) {
      var left = data.cellLeft(cell), bottom = data.cellBottom(cell);
      var size = data.cellSize;
      if (Math.abs(left + size * 0.5 - focusX) > BOUNDS_REACH || Math.abs(bottom + size * 0.5 - focusY) > BOUNDS_REACH) continue;
      var color = isLoaded(cell) ? LOADED_COLOR : UNLOADED_COLOR;
      drawEdge(overlay, left, bottom, 1, 0, color);
      drawEdge(overlay, left, bottom, 0, 1, color);
      drawEdge(overlay, left + size, bottom, 0, 1, color);
      drawEdge(overlay, left, bottom + size, 1, 0, color);
    }
  }

  public function drawNav(overlay : scene.Overlay, focusX : Float, focusY : Float) {
    if (!showNav) return;
    var step = data.cellSize / data.navResolution;
    var half = step * 0.4;
    var reach = Std.int(NAV_REACH / step);
    var left = Math.floor((focusX - data.left) / step), bottom = Math.floor((focusY - data.bottom) / step);
    for (y in bottom - reach...bottom + reach + 1)
      for (x in left - reach...left + reach + 1) {
        var px = data.left + (x + 0.5) * step, py = data.bottom + (y + 0.5) * step;
        if (navView.isWalkable(px, py)) continue;
        var z = state.terrain.heightAt(px, py) + NAV_LIFT;
        overlay.line(px - half, py - half, z, px + half, py + half, z, NAV_COLOR);
        overlay.line(px - half, py + half, z, px + half, py - half, z, NAV_COLOR);
      }
  }

  function write(files : Map<String, String>) {
    for (path => text in files) {
      File.saveContent(ROOT + path, text);
      disk.set(path, text);
      if (StringTools.endsWith(path, WorldData.NAV_SUFFIX)) for (cell in data.cells()) if (data.path(cell, WorldData.NAV_SUFFIX) == path) navView.forget(cell);
    }
  }

  function hasChanged(files : Map<String, String>, cell : Int) {
    return files.exists(data.path(cell, WorldData.OBJECTS_SUFFIX)) || files.exists(data.path(cell, WorldData.TERRAIN_SUFFIX))
      || files.exists(data.path(cell, WorldData.SCATTER_SUFFIX));
  }

  function navFiles(cells : Array<Int>) : Map<String, String> {
    var files = new Map<String, String>();
    if (cells.length == 0) return files;
    var shapes = [];
    for (entity in scene.entities) for (component in entity.components) shapes = shapes.concat(component.navShapes());
    var radius = new Map<String, Float>();
    for (type in state.view.scatterTypes()) radius.set(type.id, type.radius);
    for (cell in cells) {
      var all = shapes.copy();
      // Komşunun kayası sınırdan taşabilir, yüklü olmasa da dosyasından okunur.
      for (near in data.around(cell, 1)) {
        var text = state.scatter.exists(near) ? null : readFile(data.path(near, WorldData.SCATTER_SUFFIX));
        var items = text == null ? state.scatter.get(near) : ScatterCell.read(text);
        if (items == null) continue;
        for (item in items.items) {
          var size = radius.exists(item.type) ? radius.get(item.type) * item.scale : 0;
          if (size > 0) all.push(NavShapes.circle(item.x, item.y, size));
        }
      }
      files.set(data.path(cell, WorldData.NAV_SUFFIX), NavBaker.bake(cell, data, state.terrain, all).write());
    }
    return files;
  }

  function drawEdge(overlay : scene.Overlay, x : Float, y : Float, dx : Int, dy : Int, color : Int) {
    var step = data.step;
    for (i in 0...data.resolution) {
      var ax = x + dx * i * step, ay = y + dy * i * step;
      var bx = ax + dx * step, by = ay + dy * step;
      overlay.line(ax, ay, state.terrain.heightAt(ax, ay), bx, by, state.terrain.heightAt(bx, by), color);
    }
  }

  function loadCell(cell : Int) {
    var created = scene.instantiate(state.objects(cell).entities);
    for (entity in created) if (entity.parent == null) entity.cell = cell;
    state.loadScatter(cell);
    loaded.set(cell, true);
    dirtyRevision = -1;
  }

  function changedFiles() : Map<String, String> {
    var files = new Map<String, String>();
    function compare(path : String, text : String, isEmpty : Bool) {
      var current = diskText(path);
      if (current == null ? !isEmpty : current != text) files.set(path, text);
    }
    for (cell in [WorldData.GLOBAL].concat(loadedCells())) {
      var content = scene.toDataWhere(root -> cellOf(root) == cell);
      compare(data.path(cell, WorldData.OBJECTS_SUFFIX), SceneFormat.write(content), content.entities.length == 0);
    }
    var terrainCells = recovered == null ? [for (cell in touchedTerrain.keys()) cell] : data.cells();
    for (cell in terrainCells) compare(data.path(cell, WorldData.TERRAIN_SUFFIX), state.terrain.get(cell).write(), false);
    if (touchedEnvironment || recovered != null) compare(data.environmentPath(), state.environment.write(), false);
    var scatterCells = recovered == null ? [for (cell in touchedScatter.keys()) cell] : loadedCells();
    for (cell in scatterCells) {
      var items = state.scatter.get(cell);
      if (items != null) compare(data.path(cell, WorldData.SCATTER_SUFFIX), items.write(), items.items.length == 0);
    }
    return files;
  }

  function diskText(path : String) : Null<String> {
    if (!disk.exists(path)) disk.set(path, FileSystem.exists(ROOT + path) ? File.getContent(ROOT + path) : null);
    return disk.get(path);
  }

  function readFile(path : String) : Null<String> {
    var name = haxe.io.Path.withoutDirectory(path);
    if (recovered != null && recovered.exists(name)) return recovered.get(name);
    return diskText(path);
  }

  function get_data() {
    return state.data;
  }
}
