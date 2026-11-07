package scene.nav;

import scene.world.WorldData;
import scene.world.WorldState;

typedef NavPoint = {
  var x : Float;
  var y : Float;
}

// Dünya genelinde yol bulma. Hücreler ilk gerektiğinde okunur, bu yüzden yol yüklü olmayan
// hücrelerden de geçebilir. Yol ağı olmayan hücre tamamen yürünebilir sayılır.
// Arama bellek ayırmaz (findPathInto, NavSearch): aramanın tabloları düğüm başına diziler, geçerliliği arama numarasıyla
// (damga); yığın, yolun düğümleri ve sonucun noktaları yeniden kullanılır. Diziler ilk aramada bir kez ayrılır (dünyanın
// düğüm sayısı kadar). Bölge etiketleri de damgalı: yol ağı değişince (forget) dizi yeniden ayrılmaz; yüklemede bir kez
// etiketlenebilir (labelRegions), yoksa ilk gerektiğinde.
@:allow(scene.nav.NavSearch)
class NavWorld {
  public static inline var MAX_EXPANSIONS = 80000;
  static inline var SNAP_RINGS = 12;
  // Yol tamponlarının kurulurken ayrılan nokta sayısı (düzleştirilmiş yollar çoğunlukla kısa; uzunu tamponu büyütür).
  public static inline var PREALLOCATED_POINTS = 32;
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
    regionEpoch++;
    lastCell = -1;
    lastData = null;
  }

  // Bağlı bölgeler: birbirine yolu olan yürünebilir düğüm kümeleri (A*'ın komşuluğuyla, köşe kuralı dahil). İlk gerektiğinde
  // taşkınla etiketlenir; yol ağı değişince (forget) atılır. 0 etiketsiz, -1 engel. Hedef başka bölgedeyse (çevresi kapalı
  // cep, yayla) arama hedefe en yakın ulaşılabilir düğüme yönelir: o düğüm başlangıçtan bağımsızdır, yakın ve uzak katman
  // aynı yere varır; ulaşılamayan hedef aramaya bütün dünyayı açtırmaz (Anıt 1'in yaylası, 6 Kasım 2026).
  var regions : Null<haxe.ds.Vector<Int>>;
  var regionStamps : Null<haxe.ds.Vector<Int>>;
  var regionEpoch = 1;
  var nextRegion = 1;
  var floodQueue : Null<haxe.ds.Vector<Int>>;
  // Kendi araması (findPathInto, tek seferde) ve findPath'in tamponu.
  var own : Null<NavSearch>;
  var buffer : Array<NavPoint> = [];
  // Son okunan hücre (komşu denetimlerinin çoğu aynı hücrede: tablo araması atlanır).
  var lastCell = -1;
  var lastData : Null<NavCell>;

  // Bütün bölgeleri etiketler (yüklemede): ilk gerektiğinde etiketlemek bölgenin bütün düğümlerini o karede tarar (ana
  // bölgede milisaniyeler). Bütün hücrelerin yol ağını okur.
  public function labelRegions() {
    for (node in 0...nodesX * nodesY) regionOf(node);
  }

  function regionOf(node : Int) : Int {
    if (regions == null) {
      var n = nodesX * nodesY;
      regions = new haxe.ds.Vector(n);
      regionStamps = new haxe.ds.Vector(n);
      floodQueue = new haxe.ds.Vector(n);
      for (i in 0...n) {
        regions[i] = 0;
        regionStamps[i] = 0;
      }
    }
    if (regionStamps[node] != regionEpoch) {
      regionStamps[node] = regionEpoch;
      regions[node] = 0;
    }
    var label = regions[node];
    if (label != 0) return label;
    if (isBlocked(node % nodesX, Std.int(node / nodesX))) {
      regions[node] = -1;
      return -1;
    }
    var mark = nextRegion++, queue = floodQueue, head = 0, tail = 0;
    queue[tail++] = node;
    regions[node] = mark;
    while (head < tail) {
      var at = queue[head++], x = at % nodesX, y = Std.int(at / nodesX);
      for (dy in -1...2)
        for (dx in -1...2) {
          if (dx == 0 && dy == 0) continue;
          var nx = x + dx, ny = y + dy;
          if (isBlocked(nx, ny)) continue;
          if (dx != 0 && dy != 0 && (isBlocked(x + dx, y) || isBlocked(x, y + dy))) continue;
          var next = ny * nodesX + nx;
          if (regionStamps[next] != regionEpoch) {
            regionStamps[next] = regionEpoch;
            regions[next] = 0;
          }
          if (regions[next] != 0) continue;
          regions[next] = mark;
          queue[tail++] = next;
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
  // başlangıçtan bağımsızdır. Yeni dizi döner (editör, ajan, uzak katman); birimler findPathInto ile ayırmadan arar.
  public function findPath(fromX : Float, fromY : Float, toX : Float, toY : Float) : Array<NavPoint> {
    var count = findPathInto(fromX, fromY, toX, toY, buffer);
    return [for (i in 0...count) {x: buffer[i].x, y: buffer[i].y}];
  }

  // Yolu out'a yazar (noktaları yeniden kullanır, yalnızca dizi büyürken nokta ekler), nokta sayısını döner. out'un
  // fazlası eski aramadan kalır: sayının ötesi okunmaz. Tek seferde (karelere bölünen arama: NavSearch).
  public function findPathInto(fromX : Float, fromY : Float, toX : Float, toY : Float, out : Array<NavPoint>) : Int {
    if (own == null) own = new NavSearch(this);
    own.begin(fromX, fromY, toX, toY);
    own.step(MAX_EXPANSIONS + 1, 0);
    lastExpansions = own.expansions;
    lastReached = own.reached;
    return own.result(out);
  }

  // out'un i'nci noktası (x, y); döner: i + 1.
  inline function write(out : Array<NavPoint>, i : Int, x : Float, y : Float) : Int {
    if (i < out.length) {
      out[i].x = x;
      out[i].y = y;
    } else out.push({x: x, y: y});
    return i + 1;
  }

  inline function writeNode(out : Array<NavPoint>, i : Int, node : Int) : Int {
    return write(out, i, world.left + (node % nodesX + 0.5) * step, world.bottom + (Std.int(node / nodesX) + 0.5) * step);
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
    var cell = world.id(Std.int(x / size), Std.int(y / size));
    if (cell != lastCell) {
      lastData = cellData(cell);
      lastCell = cell;
    }
    var data = lastData;
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

// Bir yol araması: durumu kendi dizilerinde, karelere bölünebilir (npc.PathQueue: NPC yürüme emirleri kare bütçesiyle).
// begin, step (bitene kadar, istenirse bir süre sınırıyla), result. Bölünmüş arama bölünmemişle aynı yolu bulur. Arama
// sürerken yol ağı değişirse (forget) sonuç eski ağa göredir. Diziler ilk aramada bir kez ayrılır.
@:allow(scene.nav.NavWorld)
class NavSearch {
  public var done(default, null) = true;
  public var expansions(default, null) = 0;
  public var reached(default, null) = false;

  var nav : NavWorld;
  var costs : Null<haxe.ds.Vector<Float>>;
  var came : Null<haxe.ds.Vector<Int>>;
  var costStamps : Null<haxe.ds.Vector<Int>>;
  var closedStamps : Null<haxe.ds.Vector<Int>>;
  var search = 0;
  var heap = new NodeHeap();
  var trail : Array<Int> = [];
  var smoothed : Array<Int> = [];
  var start = -1;
  var end = -1;
  var best = -1;
  var bestLeft = 0.;
  var away = false;
  var toX = 0.;
  var toY = 0.;
  // Arama gerekmedi: 1 hedefin kendisi, 2 hedefe en yakın ulaşılabilir düğüm.
  var trivial = 0;

  public function new(nav : NavWorld) {
    this.nav = nav;
  }

  function prepare() {
    if (costs != null) return;
    var n = nav.nodesX * nav.nodesY;
    costs = new haxe.ds.Vector(n);
    came = new haxe.ds.Vector(n);
    costStamps = new haxe.ds.Vector(n);
    closedStamps = new haxe.ds.Vector(n);
    for (i in 0...n) {
      costStamps[i] = 0;
      closedStamps[i] = 0;
    }
  }

  // Son nokta hedeftir. Hedefe yol yoksa (hedef başka bölgede) hedefe en yakın ulaşılabilir düğüme gider; o düğüm
  // başlangıçtan bağımsızdır.
  public function begin(fromX : Float, fromY : Float, toX : Float, toY : Float) {
    this.toX = toX;
    this.toY = toY;
    expansions = 0;
    trivial = 0;
    done = false;
    start = nav.nearestOpen(nav.nodeX(fromX), nav.nodeY(fromY));
    end = nav.nearestOpen(nav.nodeX(toX), nav.nodeY(toY));
    reached = start >= 0 && end >= 0;
    if (start < 0 || end < 0) {
      trivial = 1;
      done = true;
      return;
    }
    away = false;
    var home = nav.regionOf(start);
    if (nav.regionOf(end) != home) {
      var reachable = nav.nearestInRegion(end, home);
      if (reachable >= 0) {
        end = reachable;
        away = true;
      }
    }
    if (start == end) {
      reached = !away;
      trivial = away ? 2 : 1;
      done = true;
      return;
    }
    prepare();
    search++;
    heap.clear();
    costs[start] = 0;
    costStamps[start] = search;
    came[start] = -1;
    heap.push(start, nav.estimate(start, end));
    best = start;
    bestLeft = nav.estimate(start, end);
  }

  // Düğüm açar: en çok maxExpansions kadar, deadline (haxe.Timer.stamp, sn; 0 sınırsız) gelince durur; her çağrıda en az
  // bir düğüm. Döner: arama bitti mi.
  public function step(maxExpansions : Int, deadline : Float) : Bool {
    if (done) return true;
    var opened = 0, nodesX = nav.nodesX;
    while (heap.length > 0 && expansions < NavWorld.MAX_EXPANSIONS) {
      if (opened >= maxExpansions || (deadline > 0 && opened > 0 && haxe.Timer.stamp() >= deadline)) return false;
      var node = heap.pop();
      if (node == end) {
        best = end;
        break;
      }
      if (closedStamps[node] == search) continue;
      closedStamps[node] = search;
      expansions++;
      opened++;
      var left = nav.estimate(node, end);
      if (left < bestLeft) {
        best = node;
        bestLeft = left;
      }
      var x = node % nodesX, y = Std.int(node / nodesX);
      var soFar = costs[node];
      for (dy in -1...2)
        for (dx in -1...2) {
          if (dx == 0 && dy == 0) continue;
          var nx = x + dx, ny = y + dy;
          if (nav.isBlocked(nx, ny)) continue;
          // Köşeden geçilmez: engelin ucunu sıyırmasın.
          if (dx != 0 && dy != 0 && (nav.isBlocked(x + dx, y) || nav.isBlocked(x, y + dy))) continue;
          var next = ny * nodesX + nx;
          var total = soFar + (dx != 0 && dy != 0 ? NavWorld.DIAGONAL : 1);
          if (costStamps[next] == search && costs[next] <= total) continue;
          costs[next] = total;
          costStamps[next] = search;
          came[next] = node;
          heap.push(next, total + nav.estimate(next, end));
        }
    }
    done = true;
    reached = best == end && !away;
    return true;
  }

  // Bitmiş aramanın yolu out'a (NavWorld.findPathInto gibi), nokta sayısı.
  public function result(out : Array<NavPoint>) : Int {
    if (trivial == 1) return nav.write(out, 0, toX, toY);
    if (trivial == 2) return nav.writeNode(out, 0, end);
    // Yolun düğümleri sondan başa (trail), sonra başından düzleştirilir.
    var length = 0, at = best;
    while (true) {
      if (length < trail.length) trail[length] = at;
      else trail.push(at);
      length++;
      if (at == start) break;
      at = came[at];
    }
    var count = smooth(length);
    var written = 0;
    for (i in 0...count) written = nav.writeNode(out, written, smoothed[i]);
    if (best == end && written > 0) {
      if (!away && nav.isWalkable(toX, toY)) nav.write(out, written - 1, toX, toY);
      else nav.writeNode(out, written - 1, end);
    }
    return written;
  }

  // trail sondan başa (trail[length - 1] başlangıç): düzleştirilmiş düğümler smoothed'a (başlangıç hariç), sayısı döner.
  function smooth(length : Int) : Int {
    inline function nodeAt(i : Int) return trail[length - 1 - i];
    var count = 0;
    var anchor = 0, last = length - 1;
    while (anchor < last) {
      var reached = anchor + 1;
      var probe = anchor + NavWorld.SMOOTH_STRIDE;
      while (probe < last && nav.isClear(nodeAt(anchor), nodeAt(probe))) {
        reached = probe;
        probe += NavWorld.SMOOTH_STRIDE;
      }
      if (nav.isClear(nodeAt(anchor), nodeAt(last))) reached = last;
      if (count < smoothed.length) smoothed[count] = nodeAt(reached);
      else smoothed.push(nodeAt(reached));
      count++;
      anchor = reached;
    }
    return count;
  }
}

private class NodeHeap {
  public var length(default, null) = 0;

  var nodes : Array<Int> = [];
  var scores : Array<Float> = [];

  public function new() {}

  public function clear() {
    length = 0;
  }

  public function push(node : Int, score : Float) {
    var i = length++;
    if (i < nodes.length) {
      nodes[i] = node;
      scores[i] = score;
    } else {
      nodes.push(node);
      scores.push(score);
    }
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
