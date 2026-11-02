package scene.nav;

import scene.nav.NavCell;
import scene.world.WorldData;
import scene.world.WorldTerrain;

// Hücrenin yürünemeyen yerleri: dik yamaçlar ve engeller. Saf Haxe'dir, yerel kütüphane
// gerektirmez. Aynı girdi aynı dosyayı üretir, sonuç değişmeyen hücre git farkı vermez.
class NavBaker {
  static inline var AGENT_RADIUS = 0.7;
  static inline var MAX_SLOPE_DEGREES = 42.;

  public static function bake(cell : Int, world : WorldData, terrain : WorldTerrain, shapes : Array<NavShape>) : NavCell {
    var size = world.navResolution;
    var step = world.cellSize / size;
    var left = world.cellLeft(cell), bottom = world.cellBottom(cell);
    var result = new NavCell(size);
    var limit = Math.tan(MAX_SLOPE_DEGREES * Math.PI / 180) * step;
    for (y in 0...size)
      for (x in 0...size)
        if (isSteep(terrain, left + (x + 0.5) * step, bottom + (y + 0.5) * step, step, limit)) result.block(x, y);
    for (shape in shapes) stamp(result, shape, left, bottom, step);
    return result;
  }

  static function isSteep(terrain : WorldTerrain, x : Float, y : Float, step : Float, limit : Float) {
    var half = step * 0.5;
    var a = terrain.heightAt(x - half, y - half), b = terrain.heightAt(x + half, y - half);
    var c = terrain.heightAt(x + half, y + half), d = terrain.heightAt(x - half, y + half);
    return Math.max(Math.max(a, b), Math.max(c, d)) - Math.min(Math.min(a, b), Math.min(c, d)) > limit;
  }

  static function stamp(cell : NavCell, shape : NavShape, left : Float, bottom : Float, step : Float) {
    var reach = Math.sqrt(shape.halfX * shape.halfX + shape.halfY * shape.halfY) + AGENT_RADIUS;
    var fromX = Std.int(Math.max(0, Math.floor((shape.x - reach - left) / step)));
    var toX = Std.int(Math.min(cell.size - 1, Math.ceil((shape.x + reach - left) / step)));
    var fromY = Std.int(Math.max(0, Math.floor((shape.y - reach - bottom) / step)));
    var toY = Std.int(Math.min(cell.size - 1, Math.ceil((shape.y + reach - bottom) / step)));
    for (y in fromY...toY + 1)
      for (x in fromX...toX + 1)
        if (covers(shape, left + (x + 0.5) * step, bottom + (y + 0.5) * step)) cell.block(x, y);
  }

  static function covers(shape : NavShape, x : Float, y : Float) {
    var dx = x - shape.x, dy = y - shape.y;
    if (shape.isRound) {
      var radius = shape.halfX + AGENT_RADIUS;
      return dx * dx + dy * dy <= radius * radius;
    }
    var cos = Math.cos(shape.angle), sin = Math.sin(shape.angle);
    var localX = dx * cos + dy * sin, localY = dy * cos - dx * sin;
    return Math.abs(localX) <= shape.halfX + AGENT_RADIUS && Math.abs(localY) <= shape.halfY + AGENT_RADIUS;
  }
}
