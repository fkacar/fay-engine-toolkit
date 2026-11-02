package scene.nav;

import scene.nav.NavCell;
import scene.world.WorldData;
import scene.world.WorldTerrain;

// Hücrenin yürünemeyen yerleri: dik yamaçlar ve engeller. Saf Haxe'dir, yerel kütüphane
// gerektirmez. Aynı girdi aynı dosyayı üretir, sonuç değişmeyen hücre git farkı vermez.
class NavBaker {
  static inline var AGENT_RADIUS = 0.7;

  public static function bake(cell : Int, world : WorldData, terrain : WorldTerrain, shapes : Array<NavShape>) : NavCell {
    var size = world.navResolution;
    var step = world.cellSize / size;
    var left = world.cellLeft(cell), bottom = world.cellBottom(cell);
    var result = new NavCell(size);
    var limit = world.maxSlope >= 90 ? Math.POSITIVE_INFINITY : Math.tan(world.maxSlope * Math.PI / 180) * step;
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
    var minX = shape.x, maxX = shape.x, minY = shape.y, maxY = shape.y;
    if (shape.points != null) {
      var i = 0;
      while (i + 1 < shape.points.length) {
        minX = Math.min(minX, shape.points[i]);
        maxX = Math.max(maxX, shape.points[i]);
        minY = Math.min(minY, shape.points[i + 1]);
        maxY = Math.max(maxY, shape.points[i + 1]);
        i += 2;
      }
    } else {
      var reach = Math.sqrt(shape.halfX * shape.halfX + shape.halfY * shape.halfY);
      minX -= reach;
      maxX += reach;
      minY -= reach;
      maxY += reach;
    }
    var fromX = Std.int(Math.max(0, Math.floor((minX - AGENT_RADIUS - left) / step)));
    var toX = Std.int(Math.min(cell.size - 1, Math.ceil((maxX + AGENT_RADIUS - left) / step)));
    var fromY = Std.int(Math.max(0, Math.floor((minY - AGENT_RADIUS - bottom) / step)));
    var toY = Std.int(Math.min(cell.size - 1, Math.ceil((maxY + AGENT_RADIUS - bottom) / step)));
    for (y in fromY...toY + 1)
      for (x in fromX...toX + 1)
        if (covers(shape, left + (x + 0.5) * step, bottom + (y + 0.5) * step)) cell.block(x, y);
  }

  static function covers(shape : NavShape, x : Float, y : Float) {
    if (shape.points != null) return insidePolygon(shape.points, x, y) || nearEdge(shape.points, x, y);
    var dx = x - shape.x, dy = y - shape.y;
    if (shape.isRound) {
      var radius = shape.halfX + AGENT_RADIUS;
      return dx * dx + dy * dy <= radius * radius;
    }
    var cos = Math.cos(shape.angle), sin = Math.sin(shape.angle);
    var localX = dx * cos + dy * sin, localY = dy * cos - dx * sin;
    return Math.abs(localX) <= shape.halfX + AGENT_RADIUS && Math.abs(localY) <= shape.halfY + AGENT_RADIUS;
  }

  static function insidePolygon(points : Array<Float>, x : Float, y : Float) {
    var inside = false;
    var count = Std.int(points.length / 2);
    var j = count - 1;
    for (i in 0...count) {
      var xi = points[i * 2], yi = points[i * 2 + 1], xj = points[j * 2], yj = points[j * 2 + 1];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
      j = i;
    }
    return inside;
  }

  static function nearEdge(points : Array<Float>, x : Float, y : Float) {
    var count = Std.int(points.length / 2);
    for (i in 0...count) {
      var ax = points[i * 2], ay = points[i * 2 + 1];
      var bx = points[(i + 1) % count * 2], by = points[(i + 1) % count * 2 + 1];
      var dx = bx - ax, dy = by - ay;
      var length = dx * dx + dy * dy;
      var t = length == 0 ? 0 : Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / length));
      var px = ax + dx * t - x, py = ay + dy * t - y;
      if (px * px + py * py <= AGENT_RADIUS * AGENT_RADIUS) return true;
    }
    return false;
  }
}
