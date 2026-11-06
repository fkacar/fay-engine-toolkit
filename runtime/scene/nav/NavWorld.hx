package scene.nav;

import scene.world.WorldData;
import scene.world.WorldState;

typedef NavPoint = {
  var x : Float;
  var y : Float;
}

// Dünya genelinde yol bulma. Hücreler ilk gerektiğinde okunur, bu yüzden yol yüklü olmayan
// hücrelerden de geçebilir. Yol ağı olmayan hücre tamamen yürünebilir sayılır.
class NavWorld {
  static inline var MAX_EXPANSIONS = 80000;
  static inline var SNAP_RINGS = 12;
  static inline var DIAGONAL = 1.41421356;
  static inline var SMOOTH_STRIDE = 3;
  static inline var SIGHT_SAMPLES = 4;
  static inline var SIGHT_WIDTH = 0.3;

  var state : WorldState;
  var world : WorldData;
  var step : Float;
  var nodesX : Int;
  var nodesY : Int;
  var cells = new Map<Int, Null<NavCell>>();
  // Son aramanın açtığı düğüm sayısı ve hedefe varıp varmadığı (varamazsa yol hedefe en yakın bulunan düğümde biter:
  // hedef ulaşılamaz ya da arama MAX_EXPANSIONS'a takıldı). Tanı için.
  public var lastExpansions(default, null) = 0;
  public var lastReached(default, null) = false;

  public function new(state : WorldState) {
    this.state = state;
    world = state.data;
    step = world.cellSize / world.navResolution;
    nodesX = world.columns * world.navResolution;
    nodesY = world.rows * world.navResolution;
  }

  public function forget(cell : Int) {
    cells.remove(cell);
    regions = null;
  }

  // Bağlı bölgeler: birbirine yolu olan yürünebilir düğüm kümeleri (A*'ın komşuluğuyla, köşe kuralı dahil). İlk gerektiğinde
  // taşkınla etiketlenir; yol ağı değişince (forget) atılır. 0 etiketsiz, -1 engel. Hedef başka bölgedeyse (çevresi kapalı
  // cep, yayla) arama hedefe en yakın ulaşılabilir düğüme yönelir: o düğüm başlangıçtan bağımsızdır, yakın ve uzak katman
  // aynı yere varır; ulaşılamayan hedef aramaya bütün dünyayı açtırmaz (Anıt 1'in yaylası, 6 Kasım 2026).
  var regions : Null<haxe.ds.Vector<Int>>;
  var nextRegion = 1;

  function regionOf(node : Int) : Int {
    if (regions == null) {
      regions = new haxe.ds.Vector(nodesX * nodesY);
      for (i in 0...regions.length) regions[i] = 0;
      nextRegion = 1;
    }
    var label = regions[node];
    if (label != 0) return label;
    if (isBlocked(node % nodesX, Std.int(node / nodesX))) {
      regions[node] = -1;
      return -1;
    }
    var mark = nextRegion++, queue = [node], head = 0;
    regions[node] = mark;
    while (head < queue.length) {
      var at = queue[head++], x = at % nodesX, y = Std.int(at / nodesX);
      for (dy in -1...2)
        for (dx in -1...2) {
          if (dx == 0 && dy == 0) continue;
          var nx = x + dx, ny = y + dy;
          if (isBlocked(nx, ny)) continue;
          if (dx != 0 && dy != 0 && (isBlocked(x + dx, y) || isBlocked(x, y + dy))) continue;
          var next = ny * nodesX + nx;
          if (regions[next] != 0) continue;
          regions[next] = mark;
          queue.push(next);
        }
    }
    return mark;
  }

  // Düğüme en yakın, verilen bölgedeki düğüm (halka halka dışa; ilk bulunan halkadan kökü iki katı halkaya kadar en kısa
  // düz uzaklık). Bulunamazsa -1.
  function nearestInRegion(node : Int, mark : Int) : Int {
    var cx = node % nodesX, cy = Std.int(node / nodesX), limit = Std.int(Math.max(nodesX, nodesY));
    var best = -1, bestDistance = Math.POSITIVE_INFINITY, stop = limit;
    var ring = 1;
    while (ring <= stop && ring <= limit) {
      for (i in 0...ring * 8) {
        var side = Std.int(i / (ring * 2)), t = i % (ring * 2) - ring;
        var dx = side == 0 ? t : side == 1 ? ring : side == 2 ? -t : -ring;
        var dy = side == 0 ? -ring : side == 1 ? t : side == 2 ? ring : -t;
        var x = cx + dx, y = cy + dy;
        if (x < 0 || y < 0 || x >= nodesX || y >= nodesY) continue;
        var at = y * nodesX + x;
        if (regionOf(at) != mark) continue;
        var distance = dx * dx + dy * dy;
        if (distance < bestDistance) {
          best = at;
          bestDistance = distance;
        }
      }
      if (best >= 0 && stop == limit) stop = Std.int(Math.ceil(ring * 1.4143));
      ring++;
    }
    return best;
  }

  public function isWalkable(x : Float, y : Float) {
    return !isBlocked(nodeX(x), nodeY(y));
  }

  // Yürünebilir yer: nokta yürünebilirse kendisi, değilse en yakın açık düğümün ortası; yakında açık düğüm yoksa null.
  // Sahneye bir şey konacakken (uzaktan dönen grup) bina ya da engel içine düşmesin diye.
  public function nearestWalkable(x : Float, y : Float) : Null<NavPoint> {
    if (isWalkable(x, y)) return {x: x, y: y};
    var node = nearestOpen(nodeX(x), nodeY(y));
    return node < 0 ? null : pointOf(node);
  }

  // Son nokta hedeftir. Hedefe yol yoksa (hedef başka bölgede) hedefe en yakın ulaşılabilir düğüme gider; o düğüm
  // başlangıçtan bağımsızdır.
  public function findPath(fromX : Float, fromY : Float, toX : Float, toY : Float) : Array<NavPoint> {
    var goal : NavPoint = {x: toX, y: toY};
    var start = nearestOpen(nodeX(fromX), nodeY(fromY));
    var end = nearestOpen(nodeX(toX), nodeY(toY));
    lastExpansions = 0;
    lastReached = start >= 0 && end >= 0;
    if (start < 0 || end < 0) return [goal];
    var away = false;
    var home = regionOf(start);
    if (regionOf(end) != home) {
      var reachable = nearestInRegion(end, home);
      if (reachable >= 0) {
        end = reachable;
        away = true;
      }
    }
    if (start == end) {
      lastReached = !away;
      return [away ? pointOf(end) : goal];
    }

    var open = new NodeHeap();
    var cost = new Map<Int, Float>();
    var came = new Map<Int, Int>();
    var closed = new Map<Int, Bool>();
    cost.set(start, 0);
    open.push(start, estimate(start, end));
    var best = start, bestLeft = estimate(start, end);
    var expansions = 0;
    while (open.length > 0 && expansions < MAX_EXPANSIONS) {
      var node = open.pop();
      if (node == end) {
        best = end;
        break;
      }
      if (closed.exists(node)) continue;
      closed.set(node, true);
      expansions++;
      var left = estimate(node, end);
      if (left < bestLeft) {
        best = node;
        bestLeft = left;
      }
      var x = node % nodesX, y = Std.int(node / nodesX);
      var soFar = cost.get(node);
      for (dy in -1...2)
        for (dx in -1...2) {
          if (dx == 0 && dy == 0) continue;
          var nx = x + dx, ny = y + dy;
          if (isBlocked(nx, ny)) continue;
          // Köşeden geçilmez: engelin ucunu sıyırmasın.
          if (dx != 0 && dy != 0 && (isBlocked(x + dx, y) || isBlocked(x, y + dy))) continue;
          var next = ny * nodesX + nx;
          var total = soFar + (dx != 0 && dy != 0 ? DIAGONAL : 1);
          if (cost.exists(next) && cost.get(next) <= total) continue;
          cost.set(next, total);
          came.set(next, node);
          open.push(next, total + estimate(next, end));
        }
    }
    lastExpansions = expansions;
    lastReached = best == end && !away;
    var nodes = [best];
    while (came.exists(nodes[nodes.length - 1])) nodes.push(came.get(nodes[nodes.length - 1]));
    nodes.reverse();
    var points = [for (node in smooth(nodes)) pointOf(node)];
    if (best == end) points[points.length - 1] = !away && isWalkable(toX, toY) ? goal : pointOf(end);
    return points;
  }

  function smooth(nodes : Array<Int>) {
    var result = [];
    var anchor = 0, last = nodes.length - 1;
    while (anchor < last) {
      var reached = anchor + 1;
      var probe = anchor + SMOOTH_STRIDE;
      while (probe < last && isClear(nodes[anchor], nodes[probe])) {
        reached = probe;
        probe += SMOOTH_STRIDE;
      }
      if (isClear(nodes[anchor], nodes[last])) reached = last;
      result.push(nodes[reached]);
      anchor = reached;
    }
    return result;
  }

  function isClear(from : Int, to : Int) {
    var ax = from % nodesX, ay = Std.int(from / nodesX);
    var bx = to % nodesX, by = Std.int(to / nodesX);
    var steps = Std.int(Math.max(Math.abs(bx - ax), Math.abs(by - ay))) * SIGHT_SAMPLES;
    for (i in 1...steps) {
      var t = i / steps;
      var x = ax + (bx - ax) * t, y = ay + (by - ay) * t;
      // Çizgi kapalı düğümün köşesini sıyırmasın, biraz geniş bakılır.
      if (isBlocked(Math.round(x - SIGHT_WIDTH), Math.round(y - SIGHT_WIDTH)) || isBlocked(Math.round(x + SIGHT_WIDTH), Math.round(y - SIGHT_WIDTH))
        || isBlocked(Math.round(x - SIGHT_WIDTH), Math.round(y + SIGHT_WIDTH)) || isBlocked(Math.round(x + SIGHT_WIDTH), Math.round(y + SIGHT_WIDTH))) return false;
    }
    return true;
  }

  function nearestOpen(x : Int, y : Int) {
    x = Std.int(Math.max(0, Math.min(x, nodesX - 1)));
    y = Std.int(Math.max(0, Math.min(y, nodesY - 1)));
    for (ring in 0...SNAP_RINGS)
      for (dy in -ring...ring + 1)
        for (dx in -ring...ring + 1) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) != ring) continue;
          if (!isBlocked(x + dx, y + dy)) return (y + dy) * nodesX + x + dx;
        }
    return -1;
  }

  function isBlocked(x : Int, y : Int) {
    if (x < 0 || y < 0 || x >= nodesX || y >= nodesY) return true;
    var size = world.navResolution;
    var data = cellData(world.id(Std.int(x / size), Std.int(y / size)));
    return data != null && data.isBlocked(x % size, y % size);
  }

  function cellData(cell : Int) : Null<NavCell> {
    if (cells.exists(cell)) return cells.get(cell);
    var text = state.read(world.path(cell, WorldData.NAV_SUFFIX));
    var data = text == null ? null : NavCell.read(text);
    cells.set(cell, data);
    return data;
  }

  function estimate(a : Int, b : Int) : Float {
    var dx = Math.abs(a % nodesX - b % nodesX), dy = Math.abs(Std.int(a / nodesX) - Std.int(b / nodesX));
    return Math.max(dx, dy) + (DIAGONAL - 1) * Math.min(dx, dy);
  }

  inline function nodeX(x : Float) {
    return Math.floor((x - world.left) / step);
  }

  inline function nodeY(y : Float) {
    return Math.floor((y - world.bottom) / step);
  }

  function pointOf(node : Int) : NavPoint {
    return {x: world.left + (node % nodesX + 0.5) * step, y: world.bottom + (Std.int(node / nodesX) + 0.5) * step};
  }
}

private class NodeHeap {
  public var length(default, null) = 0;

  var nodes : Array<Int> = [];
  var scores : Array<Float> = [];

  public function new() {}

  public function push(node : Int, score : Float) {
    var i = length++;
    nodes[i] = node;
    scores[i] = score;
    while (i > 0) {
      var parent = (i - 1) >> 1;
      if (scores[parent] <= scores[i]) break;
      swap(i, parent);
      i = parent;
    }
  }

  public function pop() : Int {
    var top = nodes[0];
    length--;
    nodes[0] = nodes[length];
    scores[0] = scores[length];
    var i = 0;
    while (true) {
      var left = i * 2 + 1, right = left + 1, smallest = i;
      if (left < length && scores[left] < scores[smallest]) smallest = left;
      if (right < length && scores[right] < scores[smallest]) smallest = right;
      if (smallest == i) break;
      swap(i, smallest);
      i = smallest;
    }
    return top;
  }

  function swap(a : Int, b : Int) {
    var node = nodes[a], score = scores[a];
    nodes[a] = nodes[b];
    scores[a] = scores[b];
    nodes[b] = node;
    scores[b] = score;
  }
}
