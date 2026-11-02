package scene.editor;

import scene.Overlay;
import scene.editor.commands.WorldStrokeCommand;
import scene.world.ScatterCell;
import scene.world.TerrainCell;
import scene.world.WorldData;
import scene.world.WorldState;

enum BrushTool {
  Raise;
  Lower;
  Flatten;
  Smooth;
  Paint;
  Scatter;
  Erase;
}

// Arazi ve dağıtma fırçası. Yalnızca yüklü hücreleri değiştirir. Komşusu yüklü olmayan kenar
// köşeleri kilitlidir: iki kişi komşu hücrelerde çalışınca dosyalar çakışmaz, arazi de yarılmaz.
class WorldBrush {
  static inline var SCULPT_SPEED = 12.;
  static inline var BLEND_RATE = 6.;
  static inline var CURSOR_STEPS = 48;
  static inline var CURSOR_COLOR = 0xFFFFFFFF;
  static inline var INNER_COLOR = 0x80FFFFFF;
  static inline var SCATTER_SPACING = 0.35;

  public var tool : Null<BrushTool>;
  public var radius = 15.;
  public var strength = 0.5;
  public var layer = 1;
  public var scatterType = "";
  public var density = 0.05;       // metrekare başına nesne
  public var minScale = 0.8;
  public var maxScale = 1.4;
  public var isActive(get, never) : Bool;

  var state : WorldState;
  var isEditable : Int->Bool;
  var changed : Array<Int>->Array<Int>->Void;
  var terrainBefore : Null<Map<Int, TerrainCell>>;
  var scatterBefore : Null<Map<Int, ScatterCell>>;
  var flatten = 0.;
  var lastX = 0.;
  var lastY = 0.;
  var hasLast = false;

  // changed: bir fırça darbesinden sonra değişen arazi ve dağıtma hücreleri.
  public function new(state : WorldState, isEditable : Int->Bool, changed : Array<Int>->Array<Int>->Void) {
    this.state = state;
    this.isEditable = isEditable;
    this.changed = changed;
  }

  public function begin(x : Float, y : Float) {
    terrainBefore = new Map();
    scatterBefore = new Map();
    flatten = state.terrain.heightAt(x, y);
    hasLast = false;
  }

  public function apply(x : Float, y : Float, dt : Float) {
    if (terrainBefore == null) return;
    switch (tool) {
      case Raise: sculpt(x, y, (height, weight, gx, gy) -> height + SCULPT_SPEED * strength * weight * dt);
      case Lower: sculpt(x, y, (height, weight, gx, gy) -> height - SCULPT_SPEED * strength * weight * dt);
      case Flatten: sculpt(x, y, (height, weight, gx, gy) -> blend(height, flatten, weight, dt));
      case Smooth: sculpt(x, y, (height, weight, gx, gy) -> blend(height, neighbours(gx, gy), weight, dt));
      case Paint: paint(x, y);
      case Scatter: if (hasMoved(x, y)) scatter(x, y);
      case Erase: erase(x, y);
      case null:
    }
  }

  // Darbe sırasında değişiklik uygulanır, komut bırakınca oluşur: undo'da tek adım olur.
  public function finish() : Null<WorldStrokeCommand> {
    var terrain = terrainBefore, items = scatterBefore;
    terrainBefore = null;
    scatterBefore = null;
    if (terrain == null || (Lambda.count(terrain) == 0 && Lambda.count(items) == 0)) return null;
    return WorldStrokeCommand.capture(toolLabel(), state, terrain, items, changed);
  }

  // Yükseklik haritası gibi tek seferlik işler de aynı kurallarla, tek adımda uygulanır.
  public function replaceHeights(height : (Float, Float) -> Float, label : String) : Null<WorldStrokeCommand> {
    begin(0, 0);
    var data = state.data;
    for (gy in 0...data.rows * data.resolution + 1)
      for (gx in 0...data.columns * data.resolution + 1) {
        if (!canEditVertex(gx, gy)) continue;
        remember(gx, gy);
        state.terrain.setVertexHeight(gx, gy, height(gx / (data.columns * data.resolution), gy / (data.rows * data.resolution)));
      }
    var touched = [for (cell in terrainBefore.keys()) cell];
    for (cell in touched) state.view.terrainChanged(cell);
    var terrain = terrainBefore;
    terrainBefore = null;
    scatterBefore = null;
    return Lambda.count(terrain) == 0 ? null : WorldStrokeCommand.capture(label, state, terrain, new Map(), changed);
  }

  public function drawCursor(overlay : Overlay, x : Float, y : Float) {
    circle(overlay, x, y, radius, CURSOR_COLOR);
    circle(overlay, x, y, radius * 0.5, INNER_COLOR);
  }

  function circle(overlay : Overlay, x : Float, y : Float, size : Float, color : Int) {
    var terrain = state.terrain;
    for (i in 0...CURSOR_STEPS) {
      var a = i * Math.PI * 2 / CURSOR_STEPS, b = (i + 1) * Math.PI * 2 / CURSOR_STEPS;
      var ax = x + Math.cos(a) * size, ay = y + Math.sin(a) * size;
      var bx = x + Math.cos(b) * size, by = y + Math.sin(b) * size;
      overlay.line(ax, ay, terrain.heightAt(ax, ay), bx, by, terrain.heightAt(bx, by), color);
    }
  }

  function sculpt(x : Float, y : Float, change : (Float, Float, Int, Int) -> Float) {
    var data = state.data;
    var step = data.step;
    var columns = data.columns * data.resolution, rows = data.rows * data.resolution;
    var centerX = (x - data.left) / step, centerY = (y - data.bottom) / step;
    var reach = Math.ceil(radius / step);
    var results = [];
    for (gy in Std.int(Math.max(0, Math.floor(centerY) - reach))...Std.int(Math.min(rows, Math.floor(centerY) + reach)) + 1)
      for (gx in Std.int(Math.max(0, Math.floor(centerX) - reach))...Std.int(Math.min(columns, Math.floor(centerX) + reach)) + 1) {
        var dx = (gx - centerX) * step, dy = (gy - centerY) * step;
        var distance = Math.sqrt(dx * dx + dy * dy);
        if (distance >= radius || !canEditVertex(gx, gy)) continue;
        var weight = falloff(distance / radius);
        results.push({x: gx, y: gy, height: change(state.terrain.vertexHeight(gx, gy), weight, gx, gy)});
      }
    var touched = new Map<Int, Bool>();
    for (item in results) {
      remember(item.x, item.y);
      state.terrain.setVertexHeight(item.x, item.y, item.height);
      for (cell in state.terrain.cellsOfVertex(item.x, item.y)) touched.set(cell, true);
    }
    for (cell in touched.keys()) state.view.terrainChanged(cell);
  }

  function canEditVertex(gx : Int, gy : Int) {
    return Lambda.foreach(state.terrain.cellsOfVertex(gx, gy), isEditable);
  }

  function remember(gx : Int, gy : Int) {
    for (cell in state.terrain.cellsOfVertex(gx, gy))
      if (!terrainBefore.exists(cell)) terrainBefore.set(cell, state.terrain.get(cell).clone());
  }

  function paint(x : Float, y : Float) {
    var data = state.data;
    var step = data.step;
    var touched = new Map<Int, Bool>();
    var reach = Math.ceil(radius / step);
    var centerX = Math.floor((x - data.left) / step), centerY = Math.floor((y - data.bottom) / step);
    for (qy in centerY - reach...centerY + reach + 1)
      for (qx in centerX - reach...centerX + reach + 1) {
        var px = data.left + (qx + 0.5) * step, py = data.bottom + (qy + 0.5) * step;
        var dx = px - x, dy = py - y;
        if (dx * dx + dy * dy >= radius * radius) continue;
        var cell = data.cellAt(px, py);
        if (cell == WorldData.OUTSIDE || !isEditable(cell)) continue;
        var terrain = state.terrain.get(cell);
        var ix = qx - data.columnOf(cell) * data.resolution, iy = qy - data.rowOf(cell) * data.resolution;
        if (terrain.layer(ix, iy) == layer) continue;
        if (!terrainBefore.exists(cell)) terrainBefore.set(cell, terrain.clone());
        terrain.setLayer(ix, iy, layer);
        touched.set(cell, true);
      }
    for (cell in touched.keys()) state.view.terrainChanged(cell);
  }

  function scatter(x : Float, y : Float) {
    if (scatterType == "") return;
    var area = Math.PI * radius * radius;
    var count = Math.ceil(density * area * SCATTER_SPACING);
    var spacing = 1 / Math.sqrt(density) * 0.5;
    var touched = new Map<Int, Bool>();
    for (i in 0...count) {
      var angle = Math.random() * Math.PI * 2, reach = Math.sqrt(Math.random()) * radius;
      var px = x + Math.cos(angle) * reach, py = y + Math.sin(angle) * reach;
      var cell = state.data.cellAt(px, py);
      if (cell == WorldData.OUTSIDE || !isEditable(cell)) continue;
      var items = state.scatter.get(cell);
      if (items == null) {
        items = new ScatterCell();
        state.scatter.set(cell, items);
      }
      if (isCrowded(items, px, py, spacing)) continue;
      if (!scatterBefore.exists(cell)) scatterBefore.set(cell, items.clone());
      items.items.push({type: scatterType, x: px, y: py, rotation: Math.random() * 360, scale: minScale + Math.random() * (maxScale - minScale)});
      touched.set(cell, true);
    }
    for (cell in touched.keys()) state.view.scatterChanged(cell);
  }

  function isCrowded(items : ScatterCell, x : Float, y : Float, spacing : Float) {
    for (item in items.items) {
      var dx = item.x - x, dy = item.y - y;
      if (item.type == scatterType && dx * dx + dy * dy < spacing * spacing) return true;
    }
    return false;
  }

  function erase(x : Float, y : Float) {
    var data = state.data;
    var size = data.cellSize, cellReach = Math.ceil(radius / size);
    var center = data.nearest(x, y);
    for (cell in data.around(center, cellReach)) {
      var items = state.scatter.get(cell);
      if (items == null || !isEditable(cell)) continue;
      var kept = items.items.filter(item -> {
        var dx = item.x - x, dy = item.y - y;
        return dx * dx + dy * dy >= radius * radius || (scatterType != "" && item.type != scatterType);
      });
      if (kept.length == items.items.length) continue;
      if (!scatterBefore.exists(cell)) scatterBefore.set(cell, items.clone());
      state.scatter.set(cell, new ScatterCell(kept));
      state.view.scatterChanged(cell);
    }
  }

  function hasMoved(x : Float, y : Float) {
    var dx = x - lastX, dy = y - lastY;
    if (hasLast && dx * dx + dy * dy < radius * radius * SCATTER_SPACING * SCATTER_SPACING) return false;
    lastX = x;
    lastY = y;
    hasLast = true;
    return true;
  }

  function blend(height : Float, target : Float, weight : Float, dt : Float) {
    return height + (target - height) * Math.min(1, BLEND_RATE * strength * weight * dt);
  }

  function neighbours(gx : Int, gy : Int) {
    var data = state.data;
    var maxX = data.columns * data.resolution, maxY = data.rows * data.resolution;
    var sum = 0., count = 0;
    for (offset in [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      var x = gx + offset[0], y = gy + offset[1];
      if (x < 0 || y < 0 || x > maxX || y > maxY) continue;
      sum += state.terrain.vertexHeight(x, y);
      count++;
    }
    return count == 0 ? state.terrain.vertexHeight(gx, gy) : sum / count;
  }

  static function falloff(distance : Float) {
    var t = 1 - distance;
    return t * t * (3 - 2 * t);
  }

  function toolLabel() {
    return switch (tool) {
      case Raise: "Yükselt";
      case Lower: "Alçalt";
      case Flatten: "Düzleştir";
      case Smooth: "Yumuşat";
      case Paint: "Arazi boya";
      case Scatter: "Dağıt";
      case Erase: "Dağıtılanı sil";
      case null: "Fırça";
    };
  }

  function get_isActive() {
    return tool != null;
  }
}
