package scene.save;

import haxe.DynamicAccess;
import scene.Entity;

// Oyunda kurulan nesne: kökün kimliği, hücresi, sahibi ve tam sahne verisi (SceneFormat biçiminde).
typedef CreatedRecord = {id : String, cell : Int, owner : String, scene : Dynamic};

// Oyuncunun tasarlanmış dünyada değiştirdiği (docs/KAYIT_PLANI.md):
//   durumlar: nesne kimliği → bileşen → durum; hücre kapanırken alınır, açılınca bileşenler başlamadan önce yüklenir
//   silinenler: oyunda yok edilen tasarlanmış nesneler; hücre açılınca kurulmazlar (dirilme, çoğalma olmaz)
//   oluşanlar: oyunda kurulan nesneler; tarifleri dünya dosyalarında yok, burada tam veri olarak durur
// Kayıt dosyası bunu hücre hücre yazar. Farkı olmayan nesne burada yer almaz.
class WorldDelta {
  // Hücresi olmayan nesneler (genel sahne): ekip, her zaman yüklü olanlar.
  public static inline var GLOBAL = -1;
  public static inline var PLAYER = "oyuncu";

  var states = new Map<String, DynamicAccess<Dynamic>>();
  var cells = new Map<String, Int>();
  var removed = new Map<String, Int>();
  var created = new Map<String, CreatedRecord>();
  // Oluşan bir alt ağacın her kimliği → kökü.
  var createdMember = new Map<String, String>();

  // Hücre yükleyicisi verir: dünyadaki bir noktanın hücresi (taşınan oluşan nesnenin yeni hücresi için).
  public var locate : Null<(Float, Float) -> Int>;

  public function new() {}

  // Oyunda kurulan nesnenin kimliği: seferin rastgele akışından, "o" ile başlar; editörün kimlikleriyle
  // karışmaz, kayıttan oynanınca aynı kimlikler çıkar.
  public static function newId(random : Random) : String {
    var id = new StringBuf();
    id.add("o");
    for (_ in 0...15) id.add("0123456789abcdef".charAt(random.random(16)));
    return id.toString();
  }

  public function isRemoved(id : String) : Bool {
    return removed.exists(id);
  }

  public function isCreated(id : String) : Bool {
    return createdMember.exists(id);
  }

  public function isCreatedRoot(id : String) : Bool {
    return created.exists(id);
  }

  public function ownerOf(id : String) : String {
    var root = createdMember.get(id);
    return root == null ? "" : created.get(root).owner;
  }

  // Oyunda yok edildi: nesne ve alt nesneleri. Tasarlanmışsa "silindi" işareti, oyunda kurulmuşsa kayıttan tamamen düşer.
  public function markRemoved(ids : Array<String>) {
    for (id in ids) {
      states.remove(id);
      var root = createdMember.get(id);
      if (root == null) removed.set(id, cellOf(id));
      else if (root == id) forgetCreated(id);
    }
  }

  public function recordCreated(id : String, scene : Dynamic, cell : Int, owner : String) {
    // Yenilenirken durumlar kalır (hücre kapanışında önce durum alınır, sonra veri yenilenir).
    if (created.exists(id)) forgetCreated(id, true);
    created.set(id, {id: id, cell: cell, owner: owner, scene: scene});
    var entities : Array<Dynamic> = scene.entities;
    for (item in entities) {
      createdMember.set(item.id, id);
      if (cell == GLOBAL) cells.remove(item.id) else cells.set(item.id, cell);
    }
  }

  // Oluşan nesnenin güncel hali (yer, alt nesneler); kayıt ve hücre kapanışında.
  public function updateCreated(id : String, scene : Dynamic, cell : Int) {
    var record = created.get(id);
    if (record != null) recordCreated(id, scene, cell, record.owner);
  }

  // Hücre açılırken kurulacak oluşan nesnelerin verisi (genel hücre için GLOBAL).
  public function createdIn(cell : Int) : Array<scene.data.SceneData.EntityData> {
    var items = [];
    for (record in created) if (record.cell == cell) items = items.concat(scene.data.SceneFormat.read(haxe.Json.stringify(record.scene)).entities);
    return items;
  }

  public function createdCount() : Int {
    return Lambda.count(created);
  }

  public function removedCount() : Int {
    return Lambda.count(removed);
  }

  function forgetCreated(root : String, keepStates = false) {
    var record = created.get(root);
    if (record == null) return;
    var entities : Array<Dynamic> = record.scene.entities;
    for (item in entities) {
      createdMember.remove(item.id);
      cells.remove(item.id);
      if (!keepStates) states.remove(item.id);
    }
    created.remove(root);
  }

  // Hücre yükleyicisi nesnenin hücresini bildirir: farklar hücre hücre yazılır ve silinebilir.
  public function placeIn(entity : Entity, cell : Int) {
    cells.set(entity.id, cell);
  }

  public function cellOf(id : String) : Int {
    return cells.exists(id) ? cells.get(id) : GLOBAL;
  }

  // Nesnenin Saveable bileşenlerinin farkını alır. Hiçbirinin farkı yoksa nesne listeden düşer.
  public function capture(entity : Entity) {
    if (removed.exists(entity.id)) return;
    var found : DynamicAccess<Dynamic> = {};
    var any = false;
    for (key => component in saveables(entity)) {
      var state = component.saveState();
      if (state == null) continue;
      // Kopya: bileşenin dizisi sonra değişse de alınan an korunur.
      found.set(key, haxe.Json.parse(haxe.Json.stringify(state)));
      any = true;
    }
    if (any) states.set(entity.id, found) else states.remove(entity.id);
  }

  public function captureAll(entities : Array<Entity>) {
    for (entity in entities) capture(entity);
  }

  // Bileşenler kurulduktan sonra, başlamadan önce. Geri yüklenen bileşen sayısı döner.
  public function restore(entity : Entity) : Int {
    var saved = states.get(entity.id);
    if (saved == null) return 0;
    var count = 0;
    for (key => component in saveables(entity)) {
      if (!saved.exists(key)) continue;
      component.loadState(saved.get(key));
      count++;
    }
    return count;
  }

  public function stateOf(id : String) : Null<DynamicAccess<Dynamic>> {
    return states.get(id);
  }

  public function size() : Int {
    return Lambda.count(states);
  }

  // Kimlik eşlemesi (tasarımcı yayındaki bir nesneyi silip yerine yenisini yaptı): eski kimliğin durumu yeni
  // kimliğe geçer. Eşlemeler zincirlenir: A→B, B→C ise A'nın durumu C'ye. Yeninin kendi durumu varsa o kalır.
  // Taşınan kayıt sayısı döner.
  public function remap(pairs : Map<String, String>) : Int {
    var moved = 0;
    for (from in [for (key in pairs.keys()) key]) {
      var to = from, seen = new Map<String, Bool>();
      while (pairs.exists(to) && !seen.exists(to)) {
        seen.set(to, true);
        to = pairs.get(to);
      }
      // Oyunda yok edilmiş tasarlanmış nesne yeniden yapıldıysa yenisi de kurulmaz.
      if (from != to && removed.exists(from)) {
        removed.set(to, removed.get(from));
        removed.remove(from);
      }
      if (from == to || !states.exists(from)) continue;
      if (!states.exists(to)) {
        states.set(to, states.get(from));
        if (cells.exists(from)) cells.set(to, cells.get(from));
        moved++;
      }
      states.remove(from);
      cells.remove(from);
    }
    return moved;
  }

  // Sahiplik (docs/KAYIT_PLANI.md, Import ve bölge sıfırlama): oyunda oyuncunun kurduğu nesne ya da bileşen
  // durumlarından birinde owner: "oyuncu" olan nesne (ekip üyesi). Bölge sıfırlama ve Import bunları korur.
  public function isPlayerOwned(id : String) : Bool {
    if (ownerOf(id) == PLAYER) return true;
    var saved = states.get(id);
    if (saved == null) return false;
    for (key in saved.keys()) {
      var state : Dynamic = saved.get(key);
      if (state != null && Reflect.isObject(state) && Reflect.field(state, "owner") == PLAYER) return true;
    }
    return false;
  }

  // Hikâye ilerlemesi: bileşen durumlarından birinde story: true (çalışmış "bir kez" tetikleyici). Sıfırlamalar
  // dünyanın fiziksel halini geri alır, hikâyeyi değil: görev ödülü ikinci kez alınamaz.
  public function isStory(id : String) : Bool {
    var saved = states.get(id);
    if (saved == null) return false;
    for (key in saved.keys()) {
      var state : Dynamic = saved.get(key);
      if (state != null && Reflect.isObject(state) && Reflect.field(state, "story") == true) return true;
    }
    return false;
  }

  // Bölge sıfırlama ve Import'tan sağ çıkan: oyuncunun olanlar ve hikâye ilerlemesi.
  public function survivesReset(id : String) : Bool {
    return isPlayerOwned(id) || isStory(id);
  }

  // Bölgeyi sıfırlamak: hücrenin farkı atılır, açılınca tasarlanmış haliyle gelir. Oyuncunun olanlar (kurdukları,
  // ekip) ve hikâye ilerlemesi (çalışmış tetikleyici) kalır.
  public function forgetCell(cell : Int) {
    for (id in [for (key in states.keys()) key]) if (cellOf(id) == cell && !survivesReset(id)) states.remove(id);
    for (id in [for (key in removed.keys()) key]) if (removed.get(id) == cell) removed.remove(id);
    for (id in [for (key in created.keys()) key]) if (created.get(id).cell == cell && created.get(id).owner != PLAYER) forgetCreated(id);
  }

  // Import (dünyayı sıfırla): oyuncunun olanlar ve hikâye ilerlemesi kalır. Dünyanın fiziksel farkı (NPC'ler,
  // silindi işaretleri, dünyanın kurdukları) gider; dünya tasarlanmış haliyle açılır.
  public function importPart() : WorldDelta {
    var part = new WorldDelta();
    for (record in created) if (record.owner == PLAYER) part.recordCreated(record.id, copy(record.scene), record.cell, record.owner);
    for (id => saved in states)
      if (survivesReset(id)) {
        part.states.set(id, copy(saved));
        if (cells.exists(id)) part.cells.set(id, cells.get(id));
      }
    return part;
  }

  static function copy(value : Dynamic) : Dynamic {
    return haxe.Json.parse(haxe.Json.stringify(value));
  }

  // Dosyaya: hücre → nesneler. Kimlik sırasıyla, her seferinde aynı metin.
  public function toData() : Array<{id : String, cell : Int, components : Dynamic}> {
    var ids = [for (key in states.keys()) key];
    ids.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    return [for (id in ids) {id: id, cell: cellOf(id), components: states.get(id)}];
  }

  public function removedList() : Array<{id : String, cell : Int}> {
    var ids = [for (key in removed.keys()) key];
    ids.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    return [for (id in ids) {id: id, cell: removed.get(id)}];
  }

  public function createdList() : Array<CreatedRecord> {
    var ids = [for (key in created.keys()) key];
    ids.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    return [for (id in ids) created.get(id)];
  }

  public static function fromData(items : Array<Dynamic>, ?removedItems : Array<Dynamic>, ?createdItems : Array<Dynamic>) : WorldDelta {
    var delta = new WorldDelta();
    for (item in items) {
      delta.states.set(item.id, item.components);
      if (item.cell != null && item.cell != GLOBAL) delta.cells.set(item.id, item.cell);
    }
    if (removedItems != null) for (item in removedItems) delta.removed.set(item.id, item.cell == null ? GLOBAL : item.cell);
    if (createdItems != null) for (item in createdItems) delta.recordCreated(item.id, item.scene, item.cell == null ? GLOBAL : item.cell, item.owner == null ? "" : item.owner);
    // Durumların hücresi oluşan kaydından da gelir.
    for (item in items) if (item.cell != null && item.cell != GLOBAL) delta.cells.set(item.id, item.cell);
    return delta;
  }

  // Aynı türden iki bileşen olursa sıra numarası eklenir: spawn, spawn#2.
  static function saveables(entity : Entity) : Map<String, Saveable> {
    var found = new Map<String, Saveable>();
    for (component in entity.components) {
      if (!Std.isOfType(component, Saveable)) continue;
      var saveable : Saveable = cast component;
      var key = component.componentId(), n = 2;
      while (found.exists(key)) key = component.componentId() + "#" + n++;
      found.set(key, saveable);
    }
    return found;
  }
}
