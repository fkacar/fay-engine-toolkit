package scene.editor;

import scene.Entity;
import scene.SceneInstance;
import scene.data.SceneFormat;
import scene.data.ThreeWay;
import scene.data.ThreeWay.MergeOutcome;
import scene.nav.NavBaker;
import scene.nav.NavShapes;
import scene.nav.NavWorld;
import scene.editor.TerrainModelSource.SourceModel;
import scene.editor.commands.TerrainModelCommand;
import scene.world.TerrainSurface.SurfaceGroup;
import scene.world.ScatterCell;
import scene.world.TerrainCell;
import scene.world.TerrainModelBaker;
import scene.world.TerrainModels;
import scene.world.WorldData.TerrainModel;
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
  var touchedManifest = false;
  var manifestPath = "";
  var scene : SceneInstance;
  var loaded = new Map<Int, Bool>();
  var disk = new Map<String, Null<String>>();
  var diskBinary = new Map<String, Null<haxe.io.Bytes>>();
  var recoveredDirectory : Null<String>;
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
    state.readBytes = readBinary;
    brush = new WorldBrush(state, isLoaded, canSculpt, strokeChanged);
    navView = new NavWorld(state);
  }

  public function open(cells : Array<Int>, path : String) {
    manifestPath = StringTools.startsWith(path, ROOT) ? path.substr(ROOT.length) : path;
    var saved = readFile(manifestPath);
    if (saved != null) data.assignSettings(WorldData.read(saved, data.directory));
    touchedManifest = false;
    disk = new Map();
    diskBinary = new Map();
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
    editor.commands.forget(command -> touchesCell(command, cell));
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
      for (path => bytes in changedBinaries()) changed.set(path, "");
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
    var binaries = changedBinaries();
    for (path in [for (key in binaries.keys()) key]) {
      if (binaryChanged(path, binaries.get(path))) {
        binaries.remove(path);
        editor.diskGuard.addConflict(ROOT + path, ["arazi modeli parçası"], prefer -> resolveBinary(path, prefer));
        continue;
      }
      writeBinary(path, binaries.get(path));
    }
    // Değişen hücrenin yol ağı kayıtla birlikte yenilenir, eski kalması unutulmaz.
    // Eğim veya arazi modeli değişince bütün yüklü hücrelerin yol ağı etkilenir.
    var settings = files.exists(manifestPath);
    var baked = [for (cell in loadedCells()) if (settings || hasChanged(files, cell)) cell];
    for (path => text in navFiles(baked)) if (diskText(path) != text) files.set(path, text);
    write(files);
    for (root in scene.entities) if (root.parent == null && root.cell != WorldData.GLOBAL) root.cell = cellOf(root);
    touchedTerrain = new Map();
    touchedScatter = new Map();
    touchedEnvironment = false;
    touchedManifest = false;
    recovered = null;
    recoveredDirectory = null;
    dirtyRevision = -1;
    return Lambda.count(files) + Lambda.count(binaries);
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
    for (path => bytes in changedBinaries()) if (bytes != null) File.saveBytes(directory + "/" + haxe.io.Path.withoutDirectory(path), bytes);
  }

  public function recover(directory : String, cells : Array<Int>, path : String) {
    recovered = new Map();
    recoveredDirectory = directory;
    for (name in FileSystem.readDirectory(directory))
      if (!StringTools.endsWith(name, WorldData.SURFACE_SUFFIX)) recovered.set(name, File.getContent('$directory/$name'));
    open(cells, path);
  }

  // Model altındaki hücrenin şekli modelden gelir, fırça yalnızca dağıtma yapar.
  public function canSculpt(cell : Int) {
    if (!isLoaded(cell)) return false;
    var terrain = state.terrain.get(cell);
    return terrain != null && terrain.resolution == data.resolution && !terrain.hasCoverage();
  }

  public function manifestEdited() {
    touchedManifest = true;
    dirtyRevision = -1;
  }

  public function isManifestDirty() {
    return touchedManifest && data.write() != diskText(manifestPath);
  }

  // Arazi modelleri hücre parçalarına bölünür ve yüksekliği yazılır. Her hücrenin yeni hali eskisiyle
  // karşılaştırılır, yalnızca farklı olanlar değişir: Blender'da tek tepe değişince yalnızca altındaki
  // hücreler değişir, başka birinin hücresine dokunulmaz. Değişecek hücreler yüklü olmalı.
  public function setTerrainModels(models : Array<TerrainModel>, label : String) : {ok : Bool, message : String} {
    var groups = [];
    var problems = [];
    for (model in models) {
      var source = try TerrainModelSource.load(editor.importer, model.source, data.directory + "/textures", problems) catch (e : Dynamic) {
        return {ok: false, message: '$e'};
      }
      groups = groups.concat(placeGroups(model, source));
    }
    for (problem in problems) editor.report(problem);

    var surfaces = TerrainModelBaker.surfaces(data, groups);
    var candidates = new Map<Int, Bool>();
    for (cell in data.cells()) {
      var terrain = state.terrain.get(cell);
      if (state.surfaces.exists(cell) || terrain.hasCoverage() || terrain.resolution != data.resolution) candidates.set(cell, true);
    }
    for (cell in surfaces.keys()) candidates.set(cell, true);

    // Kaplama silinir ama çözünürlük korunur: aynı model aynı sonucu verir.
    var result = new Map<Int, TerrainCell>();
    for (cell in candidates.keys()) {
      var cleared = state.terrain.get(cell).clone();
      for (i in 0...cleared.paint.length) if (cleared.paint[i] == TerrainCell.COVERED) cleared.paint[i] = 0;
      result.set(cell, cleared);
    }
    for (group in groups) {
      var baked = TerrainModelBaker.bake(data, cell -> result.exists(cell) ? result.get(cell) : state.terrain.get(cell), group.positions, group.indexes);
      for (cell => terrain in baked) {
        result.set(cell, terrain);
        candidates.set(cell, true);
      }
    }

    var before = new Map<Int, CellState>(), after = new Map<Int, CellState>();
    for (cell in candidates.keys()) {
      var terrain = result.get(cell);
      if (!surfaces.exists(cell) && !terrain.hasCoverage() && terrain.resolution != data.resolution) terrain = terrain.resample(data.resolution);
      var surface = surfaces.get(cell);
      var oldSurface = state.surfaces.get(cell);
      var sameSurface = surface == null ? oldSurface == null : oldSurface != null && surface.write().compare(oldSurface.write()) == 0;
      if (sameSurface && terrain.write() == state.terrain.get(cell).write()) continue;
      before.set(cell, {terrain: state.terrain.get(cell).clone(), surface: oldSurface});
      after.set(cell, {terrain: terrain, surface: surface});
    }
    var missing = [for (cell in before.keys()) if (!isLoaded(cell)) data.title(cell)];
    if (missing.length > 0) {
      missing.sort(Reflect.compare);
      return {ok: false, message: 'Değişecek hücreleri yükle: ${missing.join(", ")}'};
    }
    var sameModels = data.write() == withModels(models);
    if (Lambda.count(before) == 0 && sameModels) return {ok: true, message: "Model değişmemiş, hiçbir hücre değişmedi"};
    editor.commands.execute(new TerrainModelCommand(label, state, models, before, after, terrainModelsChanged));
    return {ok: true, message: '${Lambda.count(before)} hücre güncellendi'};
  }

  function withModels(models : Array<TerrainModel>) {
    var current = data.terrainModels;
    data.terrainModels = models;
    var text = data.write();
    data.terrainModels = current;
    return text;
  }

  function terrainModelsChanged(cells : Array<Int>) {
    manifestEdited();
    strokeChanged(cells, []);
  }

  function placeGroups(model : TerrainModel, source : SourceModel) : Array<SurfaceGroup> {
    return [for (group in source.groups) {
      var positions = [], normals = [], uvs = [];
      for (i in 0...Std.int(group.positions.length / 3)) {
        for (value in TerrainModels.place(model, group.positions[i * 3], group.positions[i * 3 + 1], group.positions[i * 3 + 2])) positions.push(value);
        for (value in TerrainModels.normal(model, group.normals[i * 3], group.normals[i * 3 + 1], group.normals[i * 3 + 2])) normals.push(value);
        uvs.push(group.uvs[i * 2] * model.tiling);
        uvs.push(group.uvs[i * 2 + 1] * model.tiling);
      }
      ({texture: group.texture, positions: positions, normals: normals, uvs: uvs, indexes: group.indexes} : SurfaceGroup);
    }];
  }

  public function sourceBounds(source : String) : {ok : Bool, message : String, model : Null<SourceModel>} {
    var problems = [];
    var model = try TerrainModelSource.load(editor.importer, source, data.directory + "/textures", problems) catch (e : Dynamic) {
      return {ok: false, message: '$e', model: null};
    }
    for (problem in problems) editor.report(problem);
    return {ok: true, message: "", model: model};
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

  // Yazmadan önce disk yeniden okunur: dışarıda değiştiyse birim birim birleştirilir, çakışırsa
  // yazılmaz. Yol ağı sahneden türetildiği için her zaman editörün haliyle yazılır.
  function write(files : Map<String, String>) {
    for (path in [for (key in files.keys()) key]) {
      var text = files.get(path);
      var output : Null<String> = text;
      if (!StringTools.endsWith(path, WorldData.NAV_SUFFIX)) {
        var current = DiskGuard.read(ROOT + path);
        if (current != disk.get(path)) {
          var result = merge(path, disk.get(path), text, current, null);
          if (result.text == null && result.conflicts.length > 0) {
            conflict(path, text, current, result.conflicts);
            files.remove(path);
            continue;
          }
          output = result.text;
          if (output != text) reloadFile(path, output);
        }
      }
      if (output == null) editor.diskGuard.delete(ROOT + path);
      else editor.diskGuard.write(ROOT + path, output);
      disk.set(path, output);
      if (StringTools.endsWith(path, WorldData.NAV_SUFFIX))
        for (cell in data.cells()) if (data.path(cell, WorldData.NAV_SUFFIX) == path) {
          navView.forget(cell);
          var shared = scene.service(NavWorld);
          if (shared != null) shared.forget(cell);
        }
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
    if (touchedManifest || recovered != null) compare(manifestPath, data.write(), false);
    var scatterCells = recovered == null ? [for (cell in touchedScatter.keys()) cell] : loadedCells();
    for (cell in scatterCells) {
      var items = state.scatter.get(cell);
      if (items != null) compare(data.path(cell, WorldData.SCATTER_SUFFIX), items.write(), items.items.length == 0);
    }
    return files;
  }

  // Arazi modelinin hücre parçaları: silinen parçanın değeri null'dur.
  function changedBinaries() : Map<String, Null<haxe.io.Bytes>> {
    var files = new Map<String, Null<haxe.io.Bytes>>();
    var cells = recovered == null ? [for (cell in touchedTerrain.keys()) cell] : data.cells();
    for (cell in cells) {
      var path = data.path(cell, WorldData.SURFACE_SUFFIX);
      var current = state.surfaces.get(cell), saved = binaryOnDisk(path);
      if (current == null) {
        if (saved != null) files.set(path, null);
        continue;
      }
      var bytes = current.write();
      if (saved == null || saved.compare(bytes) != 0) files.set(path, bytes);
    }
    return files;
  }

  function binaryOnDisk(path : String) : Null<haxe.io.Bytes> {
    if (!diskBinary.exists(path)) diskBinary.set(path, FileSystem.exists(ROOT + path) ? File.getBytes(ROOT + path) : null);
    return diskBinary.get(path);
  }

  function readBinary(path : String) : Null<haxe.io.Bytes> {
    var mirror = recoveredDirectory == null ? null : recoveredDirectory + "/" + haxe.io.Path.withoutDirectory(path);
    if (mirror != null && FileSystem.exists(mirror)) return File.getBytes(mirror);
    return binaryOnDisk(path);
  }

  function diskText(path : String) : Null<String> {
    if (!disk.exists(path)) {
      var text = DiskGuard.read(ROOT + path);
      disk.set(path, text);
      editor.diskGuard.observe(ROOT + path, text);
    }
    return disk.get(path);
  }

  // Açık dosyalar dışarıda değişti mi: temizse yeniden yüklenir, değilse kaydederken birleşir.
  public function checkDisk() : Array<String> {
    var reloaded = [];
    for (path in watchedFiles()) {
      var change = editor.diskGuard.changed(ROOT + path);
      if (change == null || !disk.exists(path) || change.text == disk.get(path)) continue;
      var mine = fileText(path);
      if (mine == change.text) {
        disk.set(path, change.text);
        continue;
      }
      if (!isClean(path)) {
        editor.diskGuard.pending.set(ROOT + path, true);
        continue;
      }
      try {
        reloadFile(path, change.text);
        reloaded.push(path);
      } catch (e : Dynamic) {
        editor.diskGuard.pending.set(ROOT + path, true);
        editor.show('$path okunamadı: $e', true);
      }
    }
    return reloaded;
  }

  function watchedFiles() : Array<String> {
    var files = [data.path(WorldData.GLOBAL, WorldData.OBJECTS_SUFFIX), data.environmentPath(), manifestPath];
    for (cell in data.cells()) files.push(data.path(cell, WorldData.TERRAIN_SUFFIX));
    for (cell in loadedCells()) {
      files.push(data.path(cell, WorldData.OBJECTS_SUFFIX));
      files.push(data.path(cell, WorldData.SCATTER_SUFFIX));
    }
    return files;
  }

  function merge(path : String, base : Null<String>, mine : Null<String>, theirs : Null<String>, prefer : Null<String>) : MergeOutcome {
    try {
      if (StringTools.endsWith(path, WorldData.OBJECTS_SUFFIX)) return ThreeWay.scene(base, mine, theirs, prefer);
    } catch (e : Dynamic) {
      if (prefer == null) return {text: null, conflicts: ['okunamadı: $e']};
    }
    return ThreeWay.whole(base, mine, theirs, prefer, haxe.io.Path.withoutDirectory(path));
  }

  function conflict(path : String, mine : Null<String>, theirs : Null<String>, units : Array<String>) {
    editor.diskGuard.backup(ROOT + path, mine, theirs);
    editor.diskGuard.addConflict(ROOT + path, units, prefer -> resolve(path, prefer));
  }

  // Tasarımcının seçimi: çakışmayan değişiklikler iki taraftan da kalır, çakışanda seçilen taraf.
  function resolve(path : String, prefer : String) {
    var current = DiskGuard.read(ROOT + path);
    var result = merge(path, disk.get(path), fileText(path), current, prefer);
    editor.diskGuard.removeConflict(ROOT + path);
    if (result.text == null) editor.diskGuard.delete(ROOT + path);
    else editor.diskGuard.write(ROOT + path, result.text);
    reloadFile(path, result.text);
  }

  // Dosyanın yeni hali editöre alınır. O dosyaya dokunan geri alma adımları düşer: Cmd+Z dışarıdan
  // gelen değişikliği geri almasın.
  function reloadFile(path : String, text : Null<String>) {
    disk.set(path, text);
    var cell = cellOfPath(path);
    if (StringTools.endsWith(path, WorldData.OBJECTS_SUFFIX)) {
      if (cell == WorldData.GLOBAL || isLoaded(cell)) replaceObjects(cell, text);
    } else if (StringTools.endsWith(path, WorldData.TERRAIN_SUFFIX)) {
      touchedTerrain.remove(cell);
      state.loadTerrain(cell);
    } else if (StringTools.endsWith(path, WorldData.SCATTER_SUFFIX)) {
      touchedScatter.remove(cell);
      if (isLoaded(cell)) {
        state.unloadScatter(cell);
        state.loadScatter(cell);
      }
    } else if (path == data.environmentPath()) {
      touchedEnvironment = false;
      state.reloadEnvironment();
    } else if (path == manifestPath && text != null) {
      touchedManifest = false;
      data.assignSettings(WorldData.read(text, data.directory));
    }
    dirtyRevision = -1;
  }

  function replaceObjects(cell : Int, text : Null<String>) {
    var entities = text == null ? [] : SceneFormat.read(text).entities;
    editor.commands.forget(command -> touchesCell(command, cell));
    for (root in rootsIn(cell)) scene.destroyEntity(root);
    var created = scene.instantiate(entities);
    for (entity in created) if (entity.parent == null) entity.cell = cell;
  }

  function touchesCell(command : Command, cell : Int) {
    if (Std.isOfType(command, CellCommand) && cast(command, CellCommand).touchesCell(cell)) return true;
    return Lambda.exists(command.touched(), entity -> entity.scene != null && cellOf(entity.root) == cell);
  }

  // Kaydedilmemiş dosyalar, `res/` ile başlayan yollarla.
  public function unsavedFiles() : Array<String> {
    var files = [for (path in changedFiles().keys()) ROOT + path];
    for (path in changedBinaries().keys()) files.push(ROOT + path);
    files.sort(Reflect.compare);
    return files;
  }

  public function editorText(path : String) : Null<String> {
    return fileText(StringTools.startsWith(path, ROOT) ? path.substr(ROOT.length) : path);
  }

  // Editördeki hal, kaydedilecek metin olarak.
  function fileText(path : String) : Null<String> {
    var cell = cellOfPath(path);
    if (StringTools.endsWith(path, WorldData.OBJECTS_SUFFIX)) return SceneFormat.write(scene.toDataWhere(root -> cellOf(root) == cell));
    if (StringTools.endsWith(path, WorldData.TERRAIN_SUFFIX) && state.terrain.get(cell) != null) return state.terrain.get(cell).write();
    if (StringTools.endsWith(path, WorldData.SCATTER_SUFFIX) && state.scatter.get(cell) != null) return state.scatter.get(cell).write();
    if (path == data.environmentPath()) return state.environment.write();
    if (path == manifestPath) return data.write();
    return disk.get(path);
  }

  // Kaydedilmemiş değişiklik yok mu. Nesne dosyası içerikten, diğerleri değişiklik işaretinden bilinir.
  function isClean(path : String) {
    var cell = cellOfPath(path);
    if (StringTools.endsWith(path, WorldData.OBJECTS_SUFFIX)) {
      var base = disk.get(path), mine = fileText(path);
      if (base == null) return scene.toDataWhere(root -> cellOf(root) == cell).entities.length == 0;
      return mine == (try SceneFormat.write(SceneFormat.read(base)) catch (e : Dynamic) base);
    }
    if (StringTools.endsWith(path, WorldData.TERRAIN_SUFFIX)) return !touchedTerrain.exists(cell);
    if (StringTools.endsWith(path, WorldData.SCATTER_SUFFIX)) return !touchedScatter.exists(cell);
    if (path == data.environmentPath()) return !touchedEnvironment;
    if (path == manifestPath) return !touchedManifest;
    return true;
  }

  function cellOfPath(path : String) : Int {
    for (cell in [WorldData.GLOBAL].concat(data.cells()))
      for (suffix in [WorldData.OBJECTS_SUFFIX, WorldData.TERRAIN_SUFFIX, WorldData.SCATTER_SUFFIX, WorldData.NAV_SUFFIX, WorldData.SURFACE_SUFFIX])
        if (data.path(cell, suffix) == path) return cell;
    return WorldData.OUTSIDE;
  }

  function binaryChanged(path : String, bytes : Null<haxe.io.Bytes>) {
    var current = FileSystem.exists(ROOT + path) ? File.getBytes(ROOT + path) : null;
    function same(a : Null<haxe.io.Bytes>, b : Null<haxe.io.Bytes>) return a == null ? b == null : b != null && a.compare(b) == 0;
    return !same(current, binaryOnDisk(path)) && !same(current, bytes);
  }

  function writeBinary(path : String, bytes : Null<haxe.io.Bytes>) {
    if (bytes == null) {
      if (FileSystem.exists(ROOT + path)) FileSystem.deleteFile(ROOT + path);
    } else File.saveBytes(ROOT + path, bytes);
    diskBinary.set(path, bytes);
  }

  function resolveBinary(path : String, prefer : String) {
    editor.diskGuard.removeConflict(ROOT + path);
    var cell = cellOfPath(path);
    if (prefer == ThreeWay.MINE) {
      var surface = state.surfaces.get(cell);
      writeBinary(path, surface == null ? null : surface.write());
      return;
    }
    diskBinary.set(path, FileSystem.exists(ROOT + path) ? File.getBytes(ROOT + path) : null);
    touchedTerrain.remove(cell);
    state.loadTerrain(cell);
    dirtyRevision = -1;
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
