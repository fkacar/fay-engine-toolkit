import h3d.scene.Object;
import scene.editor.ImportSettings;
import scene.Component;
import scene.ComponentRegistry;
import scene.FieldInfo.FieldHint;
import scene.FieldInfo.FieldKind;
import scene.Guid;
import scene.PlayOptions;
import scene.SceneInstance;
import scene.Entity;
import scene.data.DataTable;
import scene.story.Dialog;
import scene.story.GameState;
import scene.story.Story;
import scene.story.TriggerAction;
import scene.story.TriggerCondition;
import scene.data.GameData;
import scene.data.Prefabs;
import scene.nav.NavBaker;
import scene.nav.NavCell;
import scene.nav.NavWorld;
import scene.world.EnvironmentData;
import scene.world.CellStreamer;
import scene.world.ScatterCell;
import scene.world.TerrainCell;
import scene.world.WorldData;
import scene.world.WorldState;
import scene.world.WorldTerrain;
import scene.world.TerrainModelBaker;
import scene.world.TerrainModels;
import scene.world.TerrainSurface;
import scene.world.WorldData.TerrainModel;
import scene.world.WorldView;
import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.data.SceneSchema;
import scene.editor.CommandStack;
import scene.editor.GizmoMath;
import scene.editor.LockGroups;
import scene.editor.Selection;
import scene.editor.Validator;
import scene.editor.Vec3;
import scene.editor.WorldBrush;
import scene.editor.commands.AddComponentCommand;
import scene.editor.commands.AddEntitiesCommand;
import scene.editor.commands.GroupCommand;
import scene.editor.commands.RemoveComponentCommand;
import scene.editor.commands.RemoveEntitiesCommand;
import scene.editor.commands.SetActiveCommand;
import scene.editor.commands.SetFieldCommand;
import scene.editor.commands.SetNameCommand;
import scene.editor.commands.SetParentCommand;
import scene.editor.commands.SetTransformCommand;
import scene.editor.commands.SyncPrefabsCommand;

@:component("crate")
class Crate extends Component {
  @:editable("Genişlik", 1, 20) public var width : Float = 4;
  @:editable public var count : Int = 2;
  @:editable("Kilitli") public var locked : Bool = false;
  @:editable("Etiket") public var tag : String = "kutu";

  public var created = 0;
  public var destroyed = 0;
  public var started = 0;
  public var updates = 0;

  override function onCreate() {
    created++;
  }

  override function onDestroy() {
    destroyed++;
  }

  override function onStart() {
    started++;
  }

  override function onUpdate(dt : Float) {
    updates++;
  }
}

@:component("heavy_crate")
class HeavyCrate extends Crate {
  @:editable("Ağırlık") public var weight : Float = 100;
}

// Yeniden adlandırılmış bileşen: eski kimlik ve eski alan adı bildirilmiş.
@:component("barrel")
@:formerly("old_barrel")
class Barrel extends Component {
  @:editable @:formerly("cap", "volume_l") public var capacity : Float = 1;
}

@:component("pointer")
class Pointer extends Component {
  @:editable("Model") @:asset public var model : String = "";
  @:editable("Hedef") @:entity public var target : String = "";
  @:editable("Zorluk") @:choice("kolay", "zor") public var level : String = "kolay";
  @:editable("Renk") @:color public var tint : Int = 0xFF8000;
  @:editable("Etiketler") public var tags : Array<String> = [];
  @:editable("Hızlar") public var speeds : Array<Float> = [];
}

// Bozuk asset gibi davranır: kurulumda hata verir.
@:component("broken")
class Broken extends Component {
  override function onCreate() {
    throw "dosya bozuk";
  }
}

// Görseli nesnenin altında değil, sahne kökündedir.
@:component("walker")
class Walker extends Component {
  public var body : Object;

  override function onCreate() {
    body = new Object(entity.scene.root);
  }

  override function onDestroy() {
    body.remove();
  }

  override public function visuals() : Array<Object> {
    return [body];
  }
}

class NoIdentity extends Component {}

class NavShapes {
  public static function box2(x : Float, y : Float, halfX : Float, halfY : Float) : NavShape {
    return {x: x, y: y, halfX: halfX, halfY: halfY, angle: 0, isRound: false};
  }

  public static function circle(x : Float, y : Float, radius : Float) : NavShape {
    return {x: x, y: y, halfX: radius, halfY: radius, angle: 0, isRound: true};
  }

  public static function polygon(points : Array<Float>) : NavShape {
    return {x: points[0], y: points[1], halfX: 0, halfY: 0, angle: 0, isRound: false, points: points};
  }
}

@:component("give_count")
class GiveCount extends TriggerAction {
  override public function run(story : Story) {
    story.state.give("ekmek", 2);
  }
}

@:component("need_flag")
class NeedFlag extends TriggerCondition {
  override public function passes(story : Story) : Bool {
    return story.state.flag("izin") >= 1;
  }
}

// Oyunda sayılan, editörde görünmeyen durum: hücre kapanıp açılınca korunmalı, onStart'tan önce yüklenmeli.
@:component("sayac")
class Counter extends Component implements scene.save.Saveable {
  public var hits = 0;
  public var seenAtStart = -1;

  override function onStart() {
    seenAtStart = hits;
  }

  public function saveState() : Null<Dynamic> {
    return hits == 0 ? null : {hits: hits};
  }

  public function loadState(state : Dynamic) {
    hits = state.hits;
  }
}

@:component("traveller")
class Traveller extends Component {
  public var at = 0.;

  override public function keepsCell(isNear : (Float, Float) -> Bool) {
    return isNear(at, 0);
  }
}

class NullView implements WorldView {
  public function new() {}

  public function scatterTypes() : Array<ScatterType> {
    return [];
  }

  public function weatherPresets() : Array<WeatherPreset> {
    return [];
  }

  public function environmentChanged() {}


  public function terrainChanged(cell : Int) {}

  public function terrainRemoved(cell : Int) {}

  public function scatterChanged(cell : Int) {}

  public function scatterRemoved(cell : Int) {}
}

class TestMain {
  static var failures = 0;
  static var checks = 0;

  static function check(condition : Bool, label : String, ?pos : haxe.PosInfos) {
    checks++;
    if (!condition) {
      failures++;
      Sys.println('HATA satır ${pos.lineNumber}: $label');
    }
  }

  static function equals(actual : Dynamic, expected : Dynamic, label : String, ?pos : haxe.PosInfos) {
    check(actual == expected, '$label: beklenen <$expected>, gelen <$actual>', pos);
  }

  static function registry() {
    var types = new ComponentRegistry();
    types.register(Crate);
    types.register(HeavyCrate);
    types.register(Barrel);
    return types;
  }

  static function newScene(?mode : scene.SceneMode) {
    return new SceneInstance(registry(), mode == null ? Editor : mode, new Object());
  }

  static function sample() {
    var scene = newScene();
    var parent = scene.createEntity("Köy", "aaaaaaaaaaaaaaaa");
    parent.setPosition(1.5, -2, 0.1 + 0.2);
    var child = scene.createEntity("Ev \"1\"", "bbbbbbbbbbbbbbbb");
    child.setParent(parent);
    child.setRotation(0, 0, 45);
    child.setScale(2, 2, 2);
    var crate = child.addComponent(new HeavyCrate());
    crate.width = 7.25;
    crate.tag = "Şığ ünlü";
    return scene;
  }

  static function testNumbers() {
    equals(SceneFormat.number(0), "0", "sıfır");
    equals(SceneFormat.number(-0.0), "0", "eksi sıfır");
    equals(SceneFormat.number(1.5), "1.5", "kesir");
    equals(SceneFormat.number(-1.5), "-1.5", "negatif");
    equals(SceneFormat.number(0.1 + 0.2), "0.3", "kayan nokta gürültüsü");
    equals(SceneFormat.number(0.000001), "0", "hassasiyet altı");
    equals(SceneFormat.number(-0.000001), "0", "negatif hassasiyet altı");
    equals(SceneFormat.number(1234567.125), "1234567.125", "büyük sayı");
    equals(SceneFormat.number(10), "10", "tam sayı");
    equals(SceneFormat.number(0.05), "0.05", "baştaki sıfır");
    var thrown = false;
    try SceneFormat.number(Math.NaN) catch (e : Dynamic) thrown = true;
    check(thrown, "NaN dosyaya yazılmamalı");
  }

  static function testRoundTrip() {
    var scene = sample();
    var first = SceneFormat.write(scene.toData());
    var second = SceneFormat.write(scene.toData());
    equals(first, second, "aynı sahne iki kez aynı dosyayı üretmeli");

    var reopened = newScene();
    reopened.load(SceneFormat.read(first));
    equals(SceneFormat.write(reopened.toData()), first, "yükle ve kaydet dosyayı değiştirmemeli");

    var child = reopened.find("bbbbbbbbbbbbbbbb");
    equals(child.name, "Ev \"1\"", "kaçış karakterli ad");
    equals(child.parent.id, "aaaaaaaaaaaaaaaa", "üst nesne");
    equals(child.rotZ, 45, "dönüş");
    var crate = child.getComponent(HeavyCrate);
    equals(crate.width, 7.25, "miras alan alan");
    equals(crate.weight, 100, "alt sınıf alanı");
    equals(crate.tag, "Şığ ünlü", "Türkçe metin");
  }

  static function testEmptyScene() {
    var scene = newScene();
    var text = SceneFormat.write(scene.toData());
    var reopened = newScene();
    reopened.load(SceneFormat.read(text));
    equals(reopened.entities.length, 0, "boş sahne");
    equals(SceneFormat.write(reopened.toData()), text, "boş sahne aynı kalmalı");
  }

  static function testChildBeforeParent() {
    var data = new SceneData(SceneFormat.VERSION);
    var child = new EntityData("c", "Alt");
    child.parent = "p";
    data.entities.push(child);
    data.entities.push(new EntityData("p", "Üst"));
    var scene = newScene();
    scene.load(data);
    equals(scene.find("c").parent, scene.find("p"), "üst nesne sonra gelse de bağlanmalı");
    equals(scene.entities[0].id, "c", "dosya sırası korunmalı");
  }

  static function testMissingParent() {
    var data = new SceneData(SceneFormat.VERSION);
    var orphan = new EntityData("c", "Yetim");
    orphan.parent = "yok";
    data.entities.push(orphan);
    var scene = newScene();
    scene.load(data);
    equals(scene.warnings.length, 1, "kırık bağ uyarısı");
    equals(scene.find("c").parent, null, "yetim kökte kalmalı");
  }

  static function testUnknownDataSurvives() {
    var text = '{"version":1,"entities":[{"id":"e","name":"N","components":['
      + '{"type":"yok.Bilinmeyen","fields":{"a":[1,2],"b":{"z":1,"y":"t"}}},'
      + '{"type":"crate","fields":{"width":3,"silinenAlan":9}}]}]}';
    var scene = newScene();
    scene.load(SceneFormat.read(text));
    equals(scene.warnings.length, 2, "bilinmeyen bileşen ve alan uyarısı");
    var saved = SceneFormat.write(scene.toData());
    check(saved.indexOf('"yok.Bilinmeyen"') > 0, "bilinmeyen bileşen silinmemeli");
    check(saved.indexOf('"a": [1, 2]') > 0, "dizi alanı korunmalı");
    check(saved.indexOf('"b": {"y": "t", "z": 1}') > 0, "nesne alanı sıralı korunmalı");
    check(saved.indexOf('"silinenAlan": 9') > 0, "bilinmeyen alan silinmemeli");
    var again = newScene();
    again.load(SceneFormat.read(saved));
    equals(SceneFormat.write(again.toData()), saved, "bilinmeyen veri kararlı kalmalı");
  }

  static function testRenames() {
    var text = '{"version":1,"entities":[{"id":"e","name":"N","components":['
      + '{"type":"old_barrel","fields":{"cap":40}}]}]}';
    var scene = newScene();
    scene.load(SceneFormat.read(text));
    equals(scene.warnings.length, 0, "eski adlar uyarı vermemeli");
    var barrel = scene.find("e").getComponent(Barrel);
    check(barrel != null, "eski kimlik yeni sınıfa gitmeli");
    equals(barrel.capacity, 40, "eski alan adındaki değer korunmalı");
    var saved = SceneFormat.write(scene.toData());
    check(saved.indexOf('"type": "barrel"') > 0, "yeni kimlikle kaydedilmeli");
    check(saved.indexOf('"capacity": 40') > 0, "yeni alan adıyla kaydedilmeli");
    check(saved.indexOf("old_barrel") < 0 && saved.indexOf('"cap"') < 0, "eski adlar dosyada kalmamalı");
    var second = newScene();
    second.load(SceneFormat.read(saved));
    equals(second.find("e").getComponent(Barrel).capacity, 40, "yeni adlarla da okunmalı");
  }

  static function testRegistryErrors() {
    var types = new ComponentRegistry();
    var noId = false;
    try types.register(NoIdentity) catch (e : Dynamic) noId = true;
    check(noId, "kimliksiz bileşen reddedilmeli");
    types.register(Crate);
    var duplicate = false;
    try types.register(Crate) catch (e : Dynamic) duplicate = true;
    check(duplicate, "aynı kimlik iki kez kaydedilememeli");
    equals(new Barrel().formerIds().join(","), "old_barrel", "eski kimlik listesi");
  }

  static function testSchema() {
    var schema = new SceneSchema();
    schema.add(["barrel", "old_barrel"], ["capacity" => "Float", "cap" => "Float", "count" => "Int", "open" => "Bool", "tag" => "String"]);
    function scene(component : String) {
      return '{"version":1,"entities":[{"id":"e","name":"Varil","components":[$component]}]}';
    }
    equals(schema.check(scene('{"type":"barrel","fields":{"capacity":1.5,"count":2,"open":true,"tag":"a"}}')).length, 0, "geçerli sahne");
    equals(schema.check(scene('{"type":"old_barrel","fields":{"cap":3}}')).length, 0, "eski adlar geçerli");
    var unknownType = schema.check(scene('{"type":"crate","fields":{}}'));
    equals(unknownType.length, 1, "kodda olmayan bileşen");
    check(unknownType[0].indexOf("Varil") >= 0 && unknownType[0].indexOf("@:formerly") >= 0, "mesaj nesneyi ve çözümü söylemeli");
    equals(schema.check(scene('{"type":"barrel","fields":{"silinen":1}}')).length, 1, "kodda olmayan alan");
    equals(schema.check(scene('{"type":"barrel","fields":{"capacity":"çok"}}')).length, 1, "yanlış tip: metin");
    equals(schema.check(scene('{"type":"barrel","fields":{"count":1.5}}')).length, 1, "yanlış tip: kesirli sayı");
    equals(schema.check(scene('{"type":"barrel","fields":{"open":1}}')).length, 1, "yanlış tip: bool");
    equals(schema.check('bozuk json').length, 1, "bozuk dosya");
  }

  static function testVersions() {
    var thrown = false;
    try SceneFormat.read('{"version":999,"entities":[]}') catch (e : Dynamic) thrown = true;
    check(thrown, "yeni sürüm dosya reddedilmeli");

    var noVersion = false;
    try SceneFormat.read('{"entities":[]}') catch (e : Dynamic) noVersion = true;
    check(noVersion, "sürümsüz dosya reddedilmeli");

    var migrated = 0;
    var raw : Dynamic = haxe.Json.parse('{"version":0,"entities":[]}');
    var data = SceneFormat.parse(raw, [(_) -> migrated++]);
    equals(migrated, 1, "eski sürüm yükseltilmeli");
    equals(data.version, SceneFormat.VERSION, "sürüm güncel olmalı");
  }

  static function testMacro() {
    var crate = new HeavyCrate();
    var fields = crate.describeFields();
    equals([for (f in fields) f.name].join(","), "width,count,locked,tag,weight", "alan sırası ve miras");
    equals(fields[0].label, "Genişlik", "etiket");
    equals(fields[0].min, 1, "alt sınır");
    equals(fields[0].max, 20, "üst sınır");
    equals(fields[1].label, "count", "etiketsiz alan");
    equals(fields[1].kind, KInt, "tamsayı türü");
    equals(fields[2].kind, KBool, "bool türü");
    equals(fields[3].kind, KString, "metin türü");
    check(crate.writeField("width", 3), "alan yazılmalı");
    check(crate.writeField("weight", 5), "alt sınıf alanı yazılmalı");
    check(!crate.writeField("yok", 1), "bilinmeyen alan reddedilmeli");
    equals(crate.readField("width"), 3, "alan okunmalı");
    equals(crate.readField("weight"), 5, "alt sınıf alanı okunmalı");
    equals(crate.readField("yok"), null, "bilinmeyen alan boş dönmeli");
  }

  static function testLifecycle() {
    var editor = newScene(Editor);
    var text = SceneFormat.write(sample().toData());
    editor.load(SceneFormat.read(text));
    editor.start();
    editor.update(0.1);
    var crate = editor.find("bbbbbbbbbbbbbbbb").getComponent(HeavyCrate);
    equals(crate.created, 1, "editörde onCreate çalışmalı");
    equals(crate.started, 0, "editörde onStart çalışmamalı");
    equals(crate.updates, 0, "editörde onUpdate çalışmamalı");

    var game = newScene(Game);
    game.load(SceneFormat.read(text));
    game.start();
    game.update(0.1);
    var live = game.find("bbbbbbbbbbbbbbbb").getComponent(HeavyCrate);
    equals(live.started, 1, "oyunda onStart çalışmalı");
    equals(live.updates, 1, "oyunda onUpdate çalışmalı");
    game.find("bbbbbbbbbbbbbbbb").active = false;
    game.update(0.1);
    equals(live.updates, 1, "pasif nesne güncellenmemeli");
    game.clear();
    equals(live.destroyed, 1, "temizlikte onDestroy çalışmalı");
    equals(game.entities.length, 0, "sahne boşalmalı");
  }

  static function testCommands() {
    var scene = sample();
    var entity = scene.find("bbbbbbbbbbbbbbbb");
    var crate = entity.getComponent(HeavyCrate);
    var stack = new CommandStack();
    check(!stack.isDirty, "başta temiz");

    equals(stack.nextUndoLabel, null, "boş yığında etiket yok");
    stack.execute(new SetFieldCommand(crate, "width", crate.width, 9.0, "Genişlik"));
    equals(stack.nextUndoLabel, "Genişlik", "geri alma etiketi");
    equals(stack.undoCount, 1, "geri alınabilir adım");
    equals(crate.width, 9, "komut alanı değiştirmeli");
    equals(crate.destroyed, 1, "alan değişince görsel yeniden kurulmalı");
    check(stack.isDirty, "değişiklik kirli işaretlemeli");

    stack.undo();
    equals(crate.width, 7.25, "undo eski değeri geri getirmeli");
    check(!stack.isDirty, "undo sonrası kayıtlı hale dönmeli");
    check(stack.canRedo, "redo mümkün olmalı");
    equals(stack.nextRedoLabel, "Genişlik", "yineleme etiketi");
    equals(stack.redoCount, 1, "yinelenebilir adım");

    stack.redo();
    equals(crate.width, 9, "redo yeniden uygulamalı");
    stack.markSaved();
    check(!stack.isDirty, "kayıttan sonra temiz");
    stack.undo();
    check(stack.isDirty, "kayıttan geri gidince kirli");
    stack.redo();
    check(!stack.isDirty, "kayıtlı noktaya dönünce temiz");

    stack.undo();
    stack.execute(new SetNameCommand(entity, entity.name, "Yeni"));
    check(!stack.canRedo, "yeni komut redo'yu silmeli");
    check(stack.isDirty, "kayıtlı nokta yeni dalda kaybolmalı");
    equals(entity.name, "Yeni", "ad değişmeli");

    var before = SetTransformCommand.capture(entity);
    var after = SetTransformCommand.capture(entity);
    after.position = [5, 6, 7];
    stack.execute(new SetTransformCommand(entity, before, after));
    equals(entity.x, 5, "konum değişmeli");
    equals(entity.object.z, 7, "Heaps nesnesi güncellenmeli");
    stack.undo();
    equals(entity.x, 0, "konum geri gelmeli");
    stack.clear();
    check(!stack.canUndo && !stack.isDirty, "temizlik");
  }

  // Projedeki gerçek sahneler de kararlı olmalı: okuyup yazmak dosyayı değiştirmemeli.
  static function testProjectScenes() {
    var directory = "res/scenes";
    if (!sys.FileSystem.exists(directory)) return;
    for (name in sys.FileSystem.readDirectory(directory)) {
      if (!StringTools.endsWith(name, ".scene.json")) continue;
      var text = sys.io.File.getContent(directory + "/" + name);
      check(SceneFormat.write(SceneFormat.read(text)) == text, '$name okunup yazılınca değişmemeli');
    }
  }

  static function keep(entity : scene.Entity) {}

  static function near(actual : Float, expected : Float, label : String, ?pos : haxe.PosInfos) {
    check(Math.abs(actual - expected) < 1e-6, '$label: beklenen <$expected>, gelen <$actual>', pos);
  }

  static function testDetach() {
    var scene = sample();
    var last = scene.createEntity("Son", "cccccccccccccccc");
    var text = SceneFormat.write(scene.toData());
    var parent = scene.find("aaaaaaaaaaaaaaaa"), child = scene.find("bbbbbbbbbbbbbbbb");
    var crate = child.getComponent(HeavyCrate);

    var detached = scene.detach(parent);
    equals(scene.entities.length, 1, "alt ağaç sahneden çıkmalı");
    check(!scene.contains(child), "alt nesne de çıkmalı");
    equals(crate.destroyed, 1, "bileşen kapanmalı");
    equals(child.parent, parent, "alt ağaç bağı korunmalı");

    scene.attach(detached);
    equals(crate.created, 1, "bileşen yeniden kurulmalı");
    equals(scene.find("bbbbbbbbbbbbbbbb"), child, "aynı nesne dönmeli");
    equals(SceneFormat.write(scene.toData()), text, "geri koyma dosyayı değiştirmemeli");

    var data = scene.toDataOf([parent]);
    equals(data.entities.length, 2, "seçilen nesne alt nesneleriyle alınmalı");
    equals(data.entities[1].parent, "aaaaaaaaaaaaaaaa", "alt nesne üst bağını korumalı");
    keep(last);
  }

  static function testEntityCommands() {
    var scene = sample();
    var stack = new CommandStack();
    var text = SceneFormat.write(scene.toData());
    var parent = scene.find("aaaaaaaaaaaaaaaa"), child = scene.find("bbbbbbbbbbbbbbbb");

    // Silinen nesneye önceki komutlar da uygulanabilmeli.
    var before = SetTransformCommand.capture(child);
    var after = SetTransformCommand.capture(child);
    after.position = [9, 9, 9];
    stack.execute(new SetTransformCommand(child, before, after));
    stack.execute(new RemoveEntitiesCommand(scene, [parent]));
    equals(scene.entities.length, 0, "silinmeli");
    stack.undo();
    stack.undo();
    equals(child.x, 0, "silmeden önceki komut da geri alınmalı");
    equals(SceneFormat.write(scene.toData()), text, "geri alma dosyayı değiştirmemeli");
    stack.redo();
    stack.redo();
    equals(scene.entities.length, 0, "yineleme yeniden silmeli");
    stack.undo();
    stack.undo();

    var item = SceneFormat.read(SceneFormat.write(scene.toDataOf([child]))).entities[0];
    item.id = "dddddddddddddddd";
    var add = new AddEntitiesCommand(scene, [item], "Çoğalt");
    stack.execute(add);
    var copy = scene.find("dddddddddddddddd");
    equals(copy.parent, parent, "kopya aynı üst nesneye girmeli");
    equals(copy.getComponent(HeavyCrate).tag, "Şığ ünlü", "kopya alanları taşımalı");
    stack.undo();
    check(!scene.contains(copy), "ekleme geri alınmalı");
    equals(parent.children.length, 1, "kopya üst nesneden de çıkmalı");
    stack.redo();
    equals(scene.find("dddddddddddddddd"), copy, "yineleme aynı nesneyi geri koymalı");
    stack.undo();
    equals(SceneFormat.write(scene.toData()), text, "ekleme izi kalmamalı");

    stack.execute(new SetActiveCommand(child, false));
    check(!child.active, "oyunda kapanmalı");
    check(child.object.visible, "editörde düzenlenebilir kalmalı");
    stack.undo();
    check(child.active, "göster geri gelmeli");

    var other = scene.createEntity("Diğer", "eeeeeeeeeeeeeeee");
    var place = (entity : scene.Entity) -> entity.setPosition(3, 3, 3);
    stack.execute(new SetParentCommand(child, other, place));
    equals(child.parent, other, "üst nesne değişmeli");
    equals(child.x, 3, "konum korunmalı");
    equals(parent.children.length, 0, "eski üst nesneden çıkmalı");
    stack.undo();
    equals(child.parent, parent, "eski üst nesneye dönmeli");
    equals(child.x, 0, "konum geri gelmeli");
    stack.redo();
    equals(child.x, 3, "yineleme saklanan konumu kullanmalı");
    stack.undo();
    check(child.isInside(parent) && child.isInside(child) && !parent.isInside(child), "soy kontrolü");

    var crate = new Crate();
    stack.execute(new AddComponentCommand(parent, crate));
    equals(parent.components.length, 1, "bileşen eklenmeli");
    stack.undo();
    equals(parent.components.length, 0, "bileşen kalkmalı");
    equals(crate.destroyed, 1, "kaldırılan bileşen kapanmalı");
    stack.redo();

    var first = child.components[0];
    child.addComponent(new Crate());
    stack.execute(new RemoveComponentCommand(child, first));
    equals(child.components.length, 1, "bileşen silinmeli");
    stack.undo();
    equals(child.components[0], first, "bileşen eski sırasına dönmeli");

    var group = new GroupCommand("Grup", [new SetNameCommand(parent, parent.name, "A"), new SetNameCommand(child, child.name, "B")]);
    stack.execute(group);
    equals(child.name, "B", "grup hepsini uygulamalı");
    stack.undo();
    equals(child.name, "Ev \"1\"", "grup tek adımda geri alınmalı");
  }

  static function testVisibility() {
    var editor = sample();
    var parent = editor.find("aaaaaaaaaaaaaaaa"), child = editor.find("bbbbbbbbbbbbbbbb");
    var text = SceneFormat.write(editor.toData());
    parent.hiddenInEditor = true;
    check(!parent.object.visible, "editörde gizlenmeli");
    check(!child.isShown(), "alt nesne de görünmez sayılmalı");
    equals(SceneFormat.write(editor.toData()), text, "editörde gizleme dosyaya yazılmamalı");
    parent.hiddenInEditor = false;
    check(child.isShown(), "editörde geri gelmeli");

    parent.active = false;
    check(parent.object.visible, "oyunda gizleme editörü etkilememeli");
    check(child.isShown(), "editörde görünür kalmalı");
    check(SceneFormat.write(editor.toData()) != text, "oyunda gizleme dosyaya yazılmalı");

    var game = newScene(Game);
    game.load(editor.toData());
    var hidden = game.find("aaaaaaaaaaaaaaaa");
    check(!hidden.object.visible, "oyunda kapalı olmalı");
    check(!game.find("bbbbbbbbbbbbbbbb").isShown(), "alt nesne de kapalı olmalı");
    hidden.hiddenInEditor = true;
    hidden.active = true;
    check(hidden.object.visible, "editör bayrağı oyunu etkilememeli");

    var types = registry();
    types.register(Walker);
    var scene = new SceneInstance(types, Editor, new Object());
    var group = scene.createEntity("Grup");
    var member = scene.createEntity("Üye");
    member.setParent(group);
    @:privateAccess scene.isReady = true;
    var walker = member.addComponent(new Walker());
    group.hiddenInEditor = true;
    check(!walker.body.visible, "kök görseli üst nesneyle gizlenmeli");
    walker.refresh();
    check(!walker.body.visible, "yeniden kurulan görsel gizli kalmalı");
    group.hiddenInEditor = false;
    check(walker.body.visible, "kök görseli geri gelmeli");
  }

  static function testBrokenComponent() {
    var types = registry();
    types.register(Broken);
    var scene = new SceneInstance(types, Editor, new Object());
    var entity = scene.createEntity("Bozuk");
    @:privateAccess scene.isReady = true;
    entity.addComponent(new Broken());
    equals(scene.warnings.length, 1, "editörde hata uyarıya dönmeli");
    equals(scene.warnings[0], "Bozuk: broken kurulamadı: dosya bozuk", "uyarı metni");
    entity.components[0].refresh();
    equals(scene.warnings.length, 1, "aynı uyarı tekrarlanmamalı");

    var game = new SceneInstance(types, Game, new Object());
    @:privateAccess game.isReady = true;
    var failed = false;
    try game.createEntity("Bozuk").addComponent(new Broken()) catch (e : Dynamic) failed = true;
    check(failed, "oyunda hata gizlenmemeli");
    equals(types.currentTypes().indexOf("old_barrel"), -1, "eski kimlik ekleme listesinde olmamalı");
    check(types.currentTypes().indexOf("barrel") >= 0, "güncel kimlik listede olmalı");
  }

  static function testSelection() {
    var scene = sample();
    var parent = scene.find("aaaaaaaaaaaaaaaa"), child = scene.find("bbbbbbbbbbbbbbbb");
    var selection = new Selection();
    selection.set([child, parent]);
    equals(selection.primary, parent, "son seçilen birincil");
    equals(selection.roots().length, 1, "üstü seçili alt nesne elenmeli");
    equals(selection.roots()[0], parent, "kök üst nesne");
    selection.toggle(child);
    check(!selection.has(child), "ikinci kez seçim kaldırmalı");
    selection.add(parent);
    equals(selection.items.length, 1, "aynı nesne iki kez girmemeli");
    var detached = scene.detach(parent);
    selection.purge(scene);
    equals(selection.primary, null, "sahnede olmayan nesne seçimden çıkmalı");
    scene.attach(detached);
  }

  static function testLockGroups() {
    var scene = sample();
    var a = scene.find("aaaaaaaaaaaaaaaa"), b = scene.find("bbbbbbbbbbbbbbbb");
    var c = scene.createEntity("Üçüncü", "cccccccccccccccc");
    var d = scene.createEntity("Dördüncü", "dddddddddddddddd");
    var groups = new LockGroups();
    var selection = new Selection();
    selection.expand = list -> groups.expand(list, scene);

    check(!groups.isLocked([a, c]), "kilitsiz");
    groups.lock([a]);
    check(groups.groupOf(a) == null, "tek nesne kilitlenmez");
    groups.lock([a, c]);
    check(groups.isLocked([a, c]), "kilitli");
    check(!groups.isLocked([a, d]), "gruptan olmayan nesne");
    selection.set([a]);
    equals(selection.items.length, 2, "kilitli nesne grubuyla seçilmeli");
    selection.toggle(c);
    equals(selection.items.length, 0, "grup birlikte bırakılmalı");
    selection.add(c);
    equals(selection.items.length, 2, "grup birlikte eklenmeli");
    selection.set([d]);
    selection.toggle(a);
    equals(selection.items.length, 3, "grup seçime eklenmeli");

    groups.lock([a, d]);
    check(groups.groupOf(c) == null, "yeni kilit eski grubu çözmeli");
    equals(groups.toIds().length, 1, "tek grup kalmalı");

    var detached = scene.detach(d);
    selection.set([a]);
    equals(selection.items.length, 1, "silinen üye seçilmemeli");
    scene.attach(detached);
    selection.set([a]);
    equals(selection.items.length, 2, "geri alınan üye gruba dönmeli");

    var saved = groups.toIds();
    groups.unlock([a]);
    check(!groups.isLocked([a, d]), "kilit açılmalı");
    groups.load(saved, scene);
    check(groups.isLocked([a, d]), "kilit kayıttan dönmeli");
    groups.load([["aaaaaaaaaaaaaaaa", "ffffffffffffffff"]], scene);
    check(groups.groupOf(a) == null, "tek üye kalan grup yüklenmemeli");
    keep(b);
  }

  // Köy prefab'ı: kök, bir alt nesne ve bir ev. İç prefab Ek kutusu tek seviye iç içedir.
  static function prefabFiles() {
    var inner = new SceneData(SceneFormat.VERSION);
    var lamp = new EntityData("l0", "Lamba kökü");
    inner.entities.push(lamp);
    var light = new EntityData("l1", "Işık");
    light.parent = "l0";
    light.position = [0, 0, 3];
    inner.entities.push(light);

    var village = new SceneData(SceneFormat.VERSION);
    var root = new EntityData("r", "Köy");
    var rootCrate = new ComponentData("crate");
    rootCrate.fields.set("tag", "kök");
    root.components.push(rootCrate);
    village.entities.push(root);
    var house = new EntityData("h", "Ev");
    house.parent = "r";
    house.position = [2, 3, 0];
    var crate = new ComponentData("crate");
    crate.fields.set("width", 5);
    house.components.push(crate);
    village.entities.push(house);
    var nested = new EntityData("n", "Lamba");
    nested.parent = "r";
    nested.prefab = "lamp.prefab.json";
    village.entities.push(nested);
    return ["village.prefab.json" => SceneFormat.write(village), "lamp.prefab.json" => SceneFormat.write(inner)];
  }

  static function prefabScene(files : Map<String, String>, ?mode : scene.SceneMode) {
    var scene = newScene(mode);
    scene.prefabLoader = path -> {
      if (!files.exists(path)) throw 'dosya yok: $path';
      return files.get(path);
    };
    return scene;
  }

  static function instanceData(id : String, x : Float) {
    var item = new EntityData(id, "Köy " + id);
    item.prefab = "village.prefab.json";
    item.position = [x, 0, 0];
    var data = new SceneData(SceneFormat.VERSION);
    data.entities.push(item);
    return data;
  }

  static function testPrefabs() {
    var files = prefabFiles();
    var scene = prefabScene(files);
    scene.load(instanceData("i", 10));

    equals(scene.entities.length, 4, "instance tüm nesneleri açmalı");
    var root = scene.find("i"), house = scene.find("i/h");
    equals(root.prefab, "village.prefab.json", "kök yol taşımalı");
    equals(root.x, 10, "kök konumu instance'tan gelmeli");
    equals(root.name, "Köy i", "kök adı instance'tan gelmeli");
    equals(root.getComponent(Crate).tag, "kök", "kök bileşeni prefab'dan gelmeli");
    equals(house.parent, root, "alt nesne köke bağlanmalı");
    equals(house.x, 2, "alt nesne prefab konumunu almalı");
    equals(house.getComponent(Crate).width, 5, "bileşen alanı prefab'dan gelmeli");
    check(house.isPrefabPart && !root.isPrefabPart, "parça ayrımı");
    equals(house.instanceRoot, root, "parça köküne bağlı");
    equals(scene.find("i/n/l1").z, 3, "iç prefab tek seviye açılmalı");
    equals(scene.find("i/n/l1").parent, scene.find("i/n"), "iç prefab bağı");

    // Dosyaya yalnızca kök satırı yazılır
    var data = scene.toData();
    equals(data.entities.length, 1, "alt nesneler dosyaya yazılmamalı");
    equals(data.entities[0].components.length, 0, "bileşen prefab'da kalmalı");
    equals(data.entities[0].overrides.length, 0, "fark yok");
    var text = SceneFormat.write(data);
    equals(SceneFormat.write(SceneFormat.read(text)), text, "okuyup yazmak aynı dosyayı üretmeli");

    // Her düzenleme kendiliğinden fark olur
    house.setPosition(7, 3, 0);
    house.getComponent(Crate).width = 9;
    house.name = "Değişik";
    var changes = scene.overridesOf(root);
    equals(changes.length, 3, 'üç fark: ${[for (c in changes) c.field]}');
    equals(changes[0].target, "h", "hedef göreli kimlik");
    equals(changes[0].field, "component:crate:width", "alan sırası sabit");

    // Diske gidip gelince farklar kalır, yeniden hesap aynı dosyayı üretir
    var edited = SceneFormat.write(scene.toData());
    var reloaded = prefabScene(files);
    reloaded.load(SceneFormat.read(edited));
    equals(reloaded.find("i/h").x, 7, "konum farkı dönmeli");
    equals(reloaded.find("i/h").getComponent(Crate).width, 9, "alan farkı dönmeli");
    equals(reloaded.find("i/h").name, "Değişik", "ad farkı dönmeli");
    equals(SceneFormat.write(reloaded.toData()), edited, "fark kayıtta kararlı olmalı");
    house.setPosition(2, 3, 0);
    equals(scene.overridesOf(root).length, 2, "prefab değerine dönen alan fark olmamalı");

    // Prefab güncellenince fark olmayan alan güncellenir, fark olan kalır
    var prefab = SceneFormat.read(files.get("village.prefab.json"));
    prefab.entities[1].position = [20, 30, 0];
    var crate : ComponentData = prefab.entities[1].components[0];
    crate.fields.set("count", 42);
    crate.fields.set("width", 6);
    files.set("village.prefab.json", SceneFormat.write(prefab));
    scene.load(scene.toData());
    house = scene.find("i/h");
    equals(house.x, 20, "fark olmayan konum güncellenmeli");
    equals(house.getComponent(Crate).count, 42, "fark olmayan alan güncellenmeli");
    equals(house.getComponent(Crate).width, 9, "fark olan alan kalmalı");

    // Uygula: farklar prefab'a geçer, instance temizlenir
    root = scene.find("i");
    var changesNow = scene.overridesOf(root);
    var target = SceneFormat.read(files.get("village.prefab.json"));
    Prefabs.applyToPrefab(target, changesNow);
    files.set("village.prefab.json", SceneFormat.write(target));
    var after = scene.toData();
    after.entities[0].overrides = [];
    scene.load(after);
    equals(scene.find("i/h").getComponent(Crate).width, 9, "uygulanan değer prefab'dan gelmeli");
    equals(scene.overridesOf(scene.find("i")).length, 0, "uygulamadan sonra fark kalmamalı");

    // İç prefab farkı
    scene.find("i/n/l1").setPosition(0, 0, 8);
    var nestedChanges = scene.overridesOf(scene.find("i"));
    equals(nestedChanges.length, 1, "iç prefab farkı");
    equals(nestedChanges[0].target, "n/l1", "iç hedef yolu");
    var written = SceneFormat.write(scene.toData());
    var again = prefabScene(files);
    again.load(SceneFormat.read(written));
    equals(again.find("i/n/l1").z, 8, "iç prefab farkı dönmeli");
    var outer = SceneFormat.read(files.get("village.prefab.json"));
    Prefabs.applyToPrefab(outer, nestedChanges);
    var lampItem = Lambda.find(outer.entities, item -> item.id == "n");
    equals(lampItem.overrides.length, 1, "iç hedef instance farkına yazılmalı");
    equals(lampItem.overrides[0].target, "l1", "yol kısalmalı");

    // Aynı prefab iki kez
    var two = instanceData("a", 0);
    two.entities.push(instanceData("b", 50).entities[0]);
    var both = prefabScene(files);
    both.load(two);
    equals(both.entities.length, 8, "iki instance");
    both.find("a/h").setPosition(1, 1, 1);
    equals(both.overridesOf(both.find("b")).length, 0, "fark diğer instance'a geçmemeli");

    // Silme ve geri alma
    var stack = new CommandStack();
    var before = SceneFormat.write(both.toData());
    stack.execute(new RemoveEntitiesCommand(both, [both.find("a")]));
    equals(both.entities.length, 4, "instance parçalarıyla silinmeli");
    stack.undo();
    equals(SceneFormat.write(both.toData()), before, "silme geri alınınca dosya aynı");

    var add = new AddEntitiesCommand(both, instanceData("c", 90).entities, "Prefab ekle");
    stack.execute(add);
    equals(both.entities.length, 12, "ekleme");
    stack.undo();
    equals(both.entities.length, 8, "ekleme geri alınmalı");
    stack.redo();
    equals(both.find("c/h").parent, both.find("c"), "yineleme aynı nesneleri koymalı");

    // Kopya: kök seçilirse yalnızca kök satırı, parça seçilirse bağımsız nesne
    equals(both.toDataOf([both.find("a")]).entities.length, 1, "instance kopyası tek satır");
    var part = both.toDataOf([both.find("a/h")]);
    equals(part.entities.length, 1, "parça kopyası");
    equals(part.entities[0].prefab, null, "parça kopyası bağımsız");
    equals(part.entities[0].components.length, 1, "parça kopyası bileşen taşımalı");
  }

  static function applyFile(files : Map<String, String>, scene : SceneInstance, root : Entity) {
    var path = "village.prefab.json";
    var prefab = SceneFormat.read(files.get(path));
    Prefabs.applyToPrefab(prefab, scene.overridesOf(root));
    return {path: path, before: files.get(path), after: SceneFormat.write(prefab), write: text -> files.set(path, text)};
  }

  // Uygula ve Farkları sil normal birer undo adımıdır, önceki adımlar da çalışmaya devam eder.
  static function testPrefabUndo() {
    var files = prefabFiles();
    var two = instanceData("a", 0);
    two.entities.push(instanceData("b", 50).entities[0]);
    var scene = prefabScene(files);
    scene.load(two);
    var stack = new CommandStack();
    var root = scene.find("a"), house = scene.find("a/h"), other = scene.find("b/h");
    var crate = house.getComponent(Crate), otherCrate = other.getComponent(Crate);
    var original = files.get("village.prefab.json");

    stack.execute(new SetNameCommand(other, other.name, "Diğer"));
    stack.execute(new SetFieldCommand(crate, "width", 5, 9, "Genişlik"));

    stack.execute(new SyncPrefabsCommand("Prefab'a uygula", scene, root, applyFile(files, scene, root)));
    equals(scene.find("a/h"), house, "uygulama nesneyi yeniden kurmamalı");
    equals(house.getComponent(Crate), crate, "uygulama bileşeni yeniden kurmamalı");
    equals(otherCrate.width, 9, "diğer kopya güncellenmeli");
    equals(other.name, "Diğer", "diğer kopyanın farkı kalmalı");
    equals(scene.overridesOf(root).length, 0, "uygulanan kopyada fark kalmamalı");
    equals(scene.overridesOf(scene.find("b")).length, 1, "diğer kopyanın farkı hâlâ fark");
    check(files.get("village.prefab.json") != original, "dosya değişmeli");

    stack.undo();
    equals(files.get("village.prefab.json"), original, "geri alınca dosya aynı");
    equals(crate.width, 9, "değer fark olarak dönmeli");
    equals(scene.overridesOf(root).length, 1, "fark geri gelmeli");
    equals(otherCrate.width, 5, "diğer kopya eski değerine dönmeli");
    equals(other.name, "Diğer", "diğer kopyanın adı değişmemeli");

    stack.undo();
    equals(crate.width, 5, "önceki alan komutu çalışmalı");
    stack.undo();
    equals(other.name, "Ev", "önceki ad komutu çalışmalı");

    stack.redo();
    stack.redo();
    stack.redo();
    equals(otherCrate.width, 9, "yineleme dosyayı da uygulamalı");
    equals(scene.overridesOf(root).length, 0, "yinelemede fark yok");
    stack.undo();

    stack.execute(new SyncPrefabsCommand("Farkları sil", scene, root));
    equals(crate.width, 5, "fark silinmeli");
    equals(scene.find("a/h"), house, "fark silmek nesneyi yeniden kurmamalı");
    equals(scene.overridesOf(root).length, 0, "fark kalmamalı");
    stack.undo();
    equals(crate.width, 9, "silinen fark geri gelmeli");
    equals(scene.overridesOf(root).length, 1, "fark yeniden sayılmalı");

    // Konum ve ad da yerinde döner
    house.setPosition(40, 3, 0);
    house.name = "Taşındı";
    stack.execute(new SyncPrefabsCommand("Farkları sil", scene, root));
    equals(house.x, 2, "konum prefab'a dönmeli");
    equals(house.name, "Ev", "ad prefab'a dönmeli");
    stack.undo();
    equals(house.x, 40, "konum geri gelmeli");
    equals(house.name, "Taşındı", "ad geri gelmeli");
  }

  static function testPrefabFailures() {
    var files = prefabFiles();

    // Eksik dosya: sahne düşmez, instance kaybolmaz
    var data = instanceData("x", 4);
    data.entities[0].prefab = "yok.prefab.json";
    data.entities[0].overrides.push(new scene.data.SceneData.OverrideData("h", "name", "Kalsın"));
    var text = SceneFormat.write(data);
    var scene = prefabScene(files);
    scene.load(SceneFormat.read(text));
    equals(scene.warnings.length, 1, "eksik prefab uyarı vermeli");
    equals(scene.entities.length, 1, "kök kalmalı");
    equals(SceneFormat.write(scene.toData()), text, "yol ve farklar kaybolmamalı");

    // Oyun da çökmez: derleme eksik prefab'da durmaz, nesne boş kurulur ve uyarı yazılır.
    var game = prefabScene(files, Game);
    var failed = false;
    try game.load(SceneFormat.read(text)) catch (e : Dynamic) failed = true;
    check(!failed, "oyun eksik prefab yüzünden çökmemeli");
    equals(game.warnings.length, 1, "oyunda eksik prefab uyarı vermeli");
    equals(game.entities.length, 1, "oyunda yerinde boş nesne kalmalı");

    // Prefab'dan silinen nesnenin farkı düşer, uyarı verir
    var gone = instanceData("g", 0);
    gone.entities[0].overrides.push(new scene.data.SceneData.OverrideData("silinmis", "name", "x"));
    var other = prefabScene(files);
    other.load(gone);
    equals(other.warnings.length, 1, "hedefi olmayan fark uyarı vermeli");

    // Kendini içeren prefab sonsuza gitmez
    var loop = new SceneData(SceneFormat.VERSION);
    var head = new EntityData("a", "Baş");
    loop.entities.push(head);
    var tail = new EntityData("b", "Kuyruk");
    tail.parent = "a";
    tail.prefab = "loop.prefab.json";
    loop.entities.push(tail);
    files.set("loop.prefab.json", SceneFormat.write(loop));
    var looped = instanceData("o", 0);
    looped.entities[0].prefab = "loop.prefab.json";
    var circular = prefabScene(files);
    circular.load(looped);
    check(circular.entities.length <= 3, 'döngü bitmeli: ${circular.entities.length}');
    equals(circular.warnings.length, 1, "döngü uyarı vermeli");

    // İki köklü dosya
    var bad = new SceneData(SceneFormat.VERSION);
    bad.entities.push(new EntityData("p", "Bir"));
    bad.entities.push(new EntityData("q", "İki"));
    files.set("iki.prefab.json", SceneFormat.write(bad));
    var twoRoots = instanceData("t", 0);
    twoRoots.entities[0].prefab = "iki.prefab.json";
    var broken = prefabScene(files);
    broken.load(twoRoots);
    equals(broken.warnings.length, 1, "iki kök uyarı vermeli");

    // Prefab içi nesne referansı instance kimliğine çevrilir
    var types = registry();
    types.register(Pointer);
    var linked = new SceneData(SceneFormat.VERSION);
    var base = new EntityData("a", "Kök");
    var pointer = new ComponentData("pointer");
    pointer.fields.set("target", "b");
    base.components.push(pointer);
    linked.entities.push(base);
    var goal = new EntityData("b", "Hedef");
    goal.parent = "a";
    linked.entities.push(goal);
    var refs = new SceneInstance(types, Editor, new Object());
    refs.prefabLoader = _ -> SceneFormat.write(linked);
    var one = instanceData("i", 0);
    refs.load(one);
    equals(refs.find("i").getComponent(Pointer).target, "i/b", "referans yeni kimliği göstermeli");
    equals(refs.overridesOf(refs.find("i")).length, 0, "referans farkı sayılmamalı");
  }

  static function testPrefabSchema() {
    var schema = new SceneSchema();
    schema.add(["crate"], ["width" => "Float"]);
    var data = instanceData("i", 0);
    data.entities[0].overrides.push(new scene.data.SceneData.OverrideData("h", "component:crate:width", 4));
    equals(schema.check(SceneFormat.write(data), _ -> true).length, 0, "geçerli fark");
    equals(schema.check(SceneFormat.write(data), _ -> false).length, 0, "eksik prefab dosyası derlemeyi durdurmamalı");
    equals(schema.warnings.length, 1, "eksik prefab dosyası derlemede uyarı olmalı");
    data.entities[0].overrides[0].field = "component:crate:height";
    equals(schema.check(SceneFormat.write(data), _ -> true).length, 1, "yeniden adlandırılan alan farkta yakalanmalı");
    data.entities[0].overrides[0].field = "component:eski:width";
    equals(schema.check(SceneFormat.write(data), _ -> true).length, 1, "yeniden adlandırılan bileşen farkta yakalanmalı");
    data.entities[0].overrides[0].field = "component:crate:width";
    data.entities[0].overrides[0].value = "metin";
    equals(schema.check(SceneFormat.write(data), _ -> true).length, 1, "yanlış tip farkta yakalanmalı");
  }

  static function testGizmoMath() {
    var origin = new Vec3();
    near(GizmoMath.axisParam(new Vec3(5, 0, 10), new Vec3(0, 0, -1), origin, new Vec3(1, 0, 0)), 5, "eksen konumu");
    near(GizmoMath.axisParam(new Vec3(5, 3, 10), new Vec3(0, 0, -1), origin, new Vec3(0, 1, 0)), 3, "eksen konumu y");
    equals(GizmoMath.axisParam(origin, new Vec3(1, 0, 0), new Vec3(0, 5, 0), new Vec3(1, 0, 0)), null, "paralel eksen");
    var hit = GizmoMath.planeHit(new Vec3(1, 2, 10), new Vec3(0, 0, -1), origin, new Vec3(0, 0, 1));
    near(hit.x, 1, "düzlem x");
    near(hit.z, 0, "düzlem z");
    equals(GizmoMath.planeHit(new Vec3(0, 0, 10), new Vec3(0, 0, 1), origin, new Vec3(0, 0, 1)), null, "arkadaki düzlem");
    var a = new Vec3(0, 0, 0), b = new Vec3(2, 0, 0), c = new Vec3(0, 2, 0);
    near(GizmoMath.rayTriangle(new Vec3(0.5, 0.5, 5), new Vec3(0, 0, -1), a, b, c), 5, "üçgene çarpar");
    near(GizmoMath.rayTriangle(new Vec3(0.5, 0.5, -5), new Vec3(0, 0, 1), a, b, c), 5, "arka yüz de sayılır");
    equals(GizmoMath.rayTriangle(new Vec3(1.5, 1.5, 5), new Vec3(0, 0, -1), a, b, c), -1, "üçgenin dışı");
    equals(GizmoMath.rayTriangle(new Vec3(0.5, 0.5, 5), new Vec3(0, 0, 1), a, b, c), -1, "ışının arkası");
    equals(GizmoMath.rayTriangle(new Vec3(0.5, 0.5, 5), new Vec3(1, 0, 0), a, b, c), -1, "paralel ışın");
    near(GizmoMath.snap(2.3, 0.5), 2.5, "yakalama");
    near(GizmoMath.snap(2.3, 0), 2.3, "adım 0 değiştirmemeli");
    near(GizmoMath.segmentDistance(5, 3, 0, 0, 10, 0), 3, "doğru parçası");
    near(GizmoMath.segmentDistance(13, 4, 0, 0, 10, 0), 5, "uçtan uzaklık");
    near(GizmoMath.signedAngle(new Vec3(1, 0, 0), new Vec3(0, 1, 0), new Vec3(0, 0, 1)), Math.PI / 2, "pozitif açı");
    near(GizmoMath.signedAngle(new Vec3(1, 0, 0), new Vec3(0, -1, 0), new Vec3(0, 0, 1)), -Math.PI / 2, "negatif açı");
  }

  // Koddan çıkarılan seçenek eski dosyalarda sessizce kalmamalı.
  static function testChoiceValues() {
    var schema = new SceneSchema();
    var levels = ["kolay", "zor"];
    schema.add(["trap", "old_trap"], ["level" => "String", "grade" => "String", "name" => "String"], ["level" => levels, "grade" => levels]);
    function fileWith(type : String, field : String, value : String) {
      var data = new SceneData(SceneFormat.VERSION);
      var item = new EntityData("a", "Tuzak");
      var component = new ComponentData(type);
      component.fields.set(field, value);
      item.components.push(component);
      data.entities.push(item);
      return SceneFormat.write(data);
    }
    equals(schema.check(fileWith("trap", "level", "zor")).length, 0, "geçerli seçenek");
    var problems = schema.check(fileWith("trap", "level", "orta"));
    equals(problems.length, 1, "koddan çıkarılan seçenek yakalanmalı");
    check(problems[0].indexOf('"orta"') >= 0 && problems[0].indexOf("kolay, zor") >= 0, 'mesaj değeri ve seçenekleri söylemeli: ${problems[0]}');
    equals(schema.check(fileWith("old_trap", "level", "orta")).length, 1, "eski bileşen kimliğinde de yakalanmalı");
    equals(schema.check(fileWith("trap", "grade", "orta")).length, 1, "eski alan adında da yakalanmalı");
    equals(schema.check(fileWith("trap", "name", "orta")).length, 0, "seçenek olmayan alan serbest");

    var changed = instanceData("i", 0);
    changed.entities[0].overrides.push(new scene.data.SceneData.OverrideData("h", "component:trap:level", "orta"));
    equals(schema.check(SceneFormat.write(changed), _ -> true).length, 1, "prefab farkında da yakalanmalı");

    var types = registry();
    types.register(Pointer);
    var scene = new SceneInstance(types, Editor, new Object());
    var data = new SceneData(SceneFormat.VERSION);
    var item = new EntityData("a", "Tuzak");
    var pointer = new ComponentData("pointer");
    pointer.fields.set("level", "orta");
    item.components.push(pointer);
    data.entities.push(item);
    scene.load(data);
    var issues = new Validator(_ -> true).run(scene);
    equals(issues.length, 1, "editör geçersiz seçeneği göstermeli");
    equals(scene.find("a").getComponent(Pointer).level, "orta", "değer sessizce değiştirilmemeli");
    scene.find("a").getComponent(Pointer).level = "zor";
    equals(new Validator(_ -> true).run(scene).length, 0, "düzeltilince uyarı kalkmalı");
  }

  static function emptyWorld() {
    return new WorldData("world", 4, 3, 100, 10, [{id: "dogal", title: "Doğal", color: 0}]);
  }

  static function testWorldGrid() {
    var world = emptyWorld();
    equals(world.left, -200, "sol kenar");
    equals(world.bottom, -150, "alt kenar");
    equals(world.step, 10, "kare kenarı");
    equals(world.cellAt(-200, -150), 0, "ilk hücre");
    equals(world.cellAt(-100.5, -150), 0, "kenardan önce");
    equals(world.cellAt(-100, -150), 1, "kenar sonraki hücreye ait");
    equals(world.cellAt(199, 149), 11, "son hücre");
    equals(world.cellAt(200, 0), WorldData.OUTSIDE, "dışarısı");
    equals(world.nearest(900, -900), world.id(3, 0), "dışarıdaki nesne en yakın hücrede");
    equals(world.columnOf(6), 2, "sütun");
    equals(world.rowOf(6), 1, "satır");
    equals(world.cellLeft(6), 0, "hücre solu");
    equals(world.cellBottom(6), -50, "hücre altı");
    equals(world.path(6, WorldData.TERRAIN_SUFFIX), "world/c_2_1.terrain.json", "arazi dosyası");
    equals(world.path(WorldData.GLOBAL, WorldData.OBJECTS_SUFFIX), "world/global.scene.json", "genel dosya");
    equals(world.around(0, 1).join(","), "0,1,4,5", "köşede komşular");
    equals(world.around(5, 1)[0], 5, "merkez önce gelir");
    equals(world.around(5, 1).length, 9, "ortada dokuz hücre");
    var again = WorldData.read(world.write(), "world");
    equals(again.columns, 4, "sütun sayısı okunmalı");
    equals(again.write(), world.write(), "dünya dosyası kararlı");
    check(WorldData.isWorldFile("res/world/main.world.json"), "dünya dosyası tanınmalı");
    check(!WorldData.isWorldFile("res/scenes/main.scene.json"), "sahne dünya değil");
  }

  static function testTerrainCell() {
    var cell = TerrainCell.flat(4, 2.5);
    equals(cell.heights.length, 25, "köşe sayısı");
    equals(cell.paint.length, 16, "kare sayısı");
    cell.setHeight(1, 2, 7.126);
    cell.setLayer(3, 1, 12);
    var text = cell.write();
    var read = TerrainCell.read(text);
    equals(read.resolution, 4, "çözünürlük");
    equals(read.height(1, 2), 7.13, "yükseklik santime yuvarlanır");
    equals(read.layer(3, 1), 12, "boya");
    equals(read.write(), text, "arazi dosyası kararlı");
    check(text.split("\n").length > 10, "satır satır yazılmalı, git farkı okunur kalır");

    var scatter = new ScatterCell();
    scatter.items.push({type: "tree", x: 5, y: 1, rotation: 90, scale: 1.25});
    scatter.items.push({type: "rock", x: 2, y: 3, rotation: 0, scale: 2});
    scatter.items.push({type: "rock", x: 1, y: 3, rotation: 0, scale: 2});
    var written = scatter.write();
    var swapped = new ScatterCell([scatter.items[1], scatter.items[2], scatter.items[0]]);
    equals(swapped.write(), written, "yerleştirme sırası dosyayı değiştirmemeli");
    equals(ScatterCell.read(written).items.length, 3, "saçma okunmalı");
    equals(ScatterCell.read(written).write(), written, "saçma dosyası kararlı");
  }

  static function testWorldTerrain() {
    var world = new WorldData("world", 2, 1, 40, 4, []);
    var terrain = new WorldTerrain(world);
    equals(terrain.heightAt(0, 0), 0, "yüklü olmayan hücre sıfır");
    var left = TerrainCell.flat(4, 1), right = TerrainCell.flat(4, 1);
    for (y in 0...5) {
      left.setHeight(4, y, 5);
      right.setHeight(0, y, 5);
      right.setHeight(4, y, 9);
    }
    terrain.set(0, left);
    terrain.set(1, right);
    equals(terrain.heightAt(-40, 0), 1, "sol hücre");
    equals(terrain.heightAt(0, 0), 5, "ortak kenar");
    equals(terrain.heightAt(-5, 0), 3, "kare içinde doğrusal");
    check(Math.abs(terrain.heightAt(40, 0) - 9) < 0.01, 'sağ kenar: ${terrain.heightAt(40, 0)}');
    equals(terrain.heightAt(-999, 0), 1, "dışarısı kenardaki yüksekliği alır");
    check(terrain.contains(0, 0), "dünyanın içi");
    check(!terrain.contains(41, 0), "dünyanın dışı");
  }

  // Kayıt rastgele üretilenleri saklamaz, aynı tohumdan yeniden üretir: bu sayılar değişirse eski kayıtlardaki
  // NPC'ler başka görünür, kayalar yer değiştirir. Değerler Heaps 2.1 hxd.Rand'ından alındı (birebir kopya).
  static function testRandom() {
    var golden : Array<{seed : Int, hash : Int, ints : Array<Int>, rand : Float, srand : Float}> = [
      {seed: 0, hash: 42090530, ints: [841378, 391997, 847051, 133730], rand: 0.308883781353053, srand: -0.685819926051764},
      {seed: 1, hash: 1695882760, ints: [726613, 781775, 326192, 838364], rand: 0.578694913560508, srand: 0.468172279404417},
      {seed: 12345, hash: 665828368, ints: [93295, 663511, 350720, 389937], rand: 0.00919356450484661, srand: -0.741381033276706},
      {seed: -7, hash: 2135320727, ints: [183542, 926618, 403958, 316073], rand: 0.0224842610172879, srand: -0.50314779654242},
    ];
    for (g in golden) {
      var r = new scene.save.Random(g.seed);
      equals(scene.save.Random.hash(g.seed), g.hash, 'karma ${g.seed}');
      equals([for (_ in 0...4) r.random(1000000)].join(","), g.ints.join(","), 'tam sayılar ${g.seed}');
      check(Math.abs(r.rand() - g.rand) < 1e-12, 'rand ${g.seed}');
      check(Math.abs(r.srand() - g.srand) < 1e-12, 'srand ${g.seed}');
    }
    equals(scene.save.Random.textSeed("2f37e6920111c0d0:0"), 1690738351, "görünüş tohumu (FNV-1a)");
    equals(scene.save.Random.layoutSeed("2f37e6920111c0d0"), 5915597, "doğma alanı yerleşim tohumu");

    var streams = new scene.save.RandomStreams(424242);
    var loot = streams.get("ganimet");
    for (_ in 0...5) loot.rand();
    streams.get("dovus").rand();
    var copy = scene.save.RandomStreams.fromData(haxe.Json.parse(haxe.Json.stringify(streams.toData())));
    equals(copy.get("ganimet").random(1000000), streams.get("ganimet").random(1000000), "akış kayıttan aynı noktadan sürmeli");
    var fresh = new scene.save.RandomStreams(424242);
    fresh.get("dovus");
    var first = fresh.get("ganimet").random(1000000);
    equals(new scene.save.RandomStreams(424242).get("ganimet").random(1000000), first, "bir akışa çekiliş eklemek ötekini kaydırmamalı");

    // Bekçi: oyun ve araç takımı kodunda tohumsuz rastgelelik yok. İstisnalar: editörün kimlik üretimi, sefer kimliği.
    var allowed = ["Guid.hx", "SaveSlots.hx"];
    var banned = ~/Math\.random|Std\.random|hxd\.Rand/;
    var found = [];
    function scan(dir : String) {
      for (name in sys.FileSystem.readDirectory(dir)) {
        var path = '$dir/$name';
        if (sys.FileSystem.isDirectory(path)) scan(path);
        else if (StringTools.endsWith(name, ".hx") && allowed.indexOf(name) < 0)
          for (line in sys.io.File.getContent(path).split("\n")) {
            var code = line.indexOf("//") >= 0 ? line.substr(0, line.indexOf("//")) : line;
            if (banned.match(code)) found.push('$path: ${StringTools.trim(line)}');
          }
      }
    }
    var roots = ["libs/scene-toolkit/runtime", "runtime", "src"].filter(dir -> sys.FileSystem.exists(dir) && sys.FileSystem.isDirectory(dir));
    check(roots.length > 0, "taranacak kod klasörü bulunmalı");
    for (dir in roots) scan(dir);
    equals(found.join(" | "), "", "tohumsuz rastgelelik (scene.save.Random kullan)");
  }

  // Oyunda silinen ve oyunda kurulan nesneler: dirilme, kaybolma, hücre sızıntısı olmamalı.
  static function testRuntimeEntities() {
    var world = new WorldData("world", 5, 1, 10, 2, []);
    var files = new Map<String, String>();
    for (cell in world.cells()) {
      var data = new SceneData(SceneFormat.VERSION);
      var item = new EntityData("n" + cell, "Sayaç " + cell);
      item.components.push(new ComponentData("sayac"));
      data.entities.push(item);
      files.set(world.path(cell, WorldData.OBJECTS_SUFFIX), SceneFormat.write(data));
    }
    var types = registry();
    types.register(Counter);
    function made(id : String, x : Float) {
      var data = new SceneData(SceneFormat.VERSION);
      var item = new EntityData(id, "Kulübe " + id);
      item.position = [x, 0, 0];
      item.components.push(new ComponentData("sayac"));
      data.entities.push(item);
      return data;
    }
    function open(delta : scene.save.WorldDelta) {
      var game = new SceneInstance(types, Game, new Object());
      game.delta = delta;
      var streamer = new CellStreamer(new WorldState(world, path -> files.get(path)), game, true);
      streamer.objectRadius = 0;
      streamer.start(world.cellLeft(0) + 1, 0);
      game.start();
      return {game: game, streamer: streamer};
    }
    var delta = new scene.save.WorldDelta();
    var run = open(delta), game = run.game, streamer = run.streamer;
    var far = world.cellLeft(4) + 1, home = world.cellLeft(0) + 1;

    game.removeEntity(game.find("n0"));
    check(game.find("n0") == null && delta.isRemoved("n0"), "oyunda silinen nesne gitmeli, işaretlenmeli");
    game.spawnEntities(made("o1", world.cellLeft(0) + 3), 0, scene.save.WorldDelta.PLAYER);
    game.find("o1").getComponent(Counter).hits = 4;
    var moving = game.spawnEntities(made("o2", world.cellLeft(0) + 4), 0)[0];
    moving.setPosition(world.cellLeft(4) + 3, 0, 0);
    streamer.update(far, 0);
    check(game.find("o1") == null, "oyunda kurulan nesne hücreyle kapanmalı (sızıntı yok)");
    check(game.find("o2") != null, "başka hücreye taşınan nesne eski hücreyle kapanmamalı");
    equals(game.entities.filter(e -> e.id == "o2").length, 1, "taşınan nesne yeni hücresinde ikinci kez kurulmamalı");
    streamer.update(home, 0);
    check(game.find("n0") == null, "silinen nesne hücre açılınca dirilmemeli");
    var hut = game.find("o1");
    check(hut != null && hut.getComponent(Counter).hits == 4 && hut.getComponent(Counter).seenAtStart == 4, "kurulan nesne durumuyla geri gelmeli");

    // Dosyaya yazılıp yeni bir sahnede açılınca aynı dünya.
    game.captureDelta();
    var text = haxe.Json.stringify({states: delta.toData(), removed: delta.removedList(), created: delta.createdList()});
    var saved : Dynamic = haxe.Json.parse(text);
    var copy = open(scene.save.WorldDelta.fromData(saved.states, saved.removed, saved.created));
    check(copy.game.find("n0") == null && copy.game.find("o1") != null && copy.game.find("o1").getComponent(Counter).hits == 4, "kayıttan açılınca silinen yok, kurulan durumuyla var");
    check(copy.game.find("o2") == null, "taşınan nesne yeni hücresinde, o hücre kapalıyken kurulmaz");
    copy.streamer.update(far, 0);
    check(copy.game.find("o2") != null, "taşınan nesne yeni hücresi açılınca gelmeli");

    // Oyunda kurulan nesneyi yok etmek kayıttan tamamen düşürür; bölge sıfırlama oyuncununkini korur.
    game.removeEntity(game.find("o1"));
    check(!delta.isCreated("o1"), "yok edilen kurulan nesne kayıttan düşmeli");
    game.spawnEntities(made("o3", world.cellLeft(0) + 5), 0);
    game.spawnEntities(made("o4", world.cellLeft(0) + 6), 0, scene.save.WorldDelta.PLAYER);
    streamer.update(far, 0);
    delta.forgetCell(0);
    check(!delta.isCreated("o3") && delta.isCreated("o4") && !delta.isRemoved("n0"), "bölge sıfırlanınca dünyanınki gider, oyuncununki kalır, silinen geri gelir");
    streamer.update(home, 0);
    check(game.find("n0") != null && game.find("o4") != null && game.find("o3") == null, "sıfırlanan bölge tasarlanmış hali ve oyuncunun kurduklarıyla");

    // Genel hücreye kurulan (ekibe katılan) her zaman yüklü, kayıttan açılışta gelir.
    game.spawnEntities(made("o5", 0), scene.save.WorldDelta.GLOBAL, scene.save.WorldDelta.PLAYER);
    game.captureDelta();
    var again : Dynamic = haxe.Json.parse(haxe.Json.stringify({states: delta.toData(), removed: delta.removedList(), created: delta.createdList()}));
    var third = open(scene.save.WorldDelta.fromData(again.states, again.removed, again.created));
    check(third.game.find("o5") != null, "genel hücredeki kurulan nesne açılışta gelmeli");
    // Sahiplik bileşenin durumunda (owner): bölge sıfırlama korur. Import yalnızca oyuncununkileri taşır.
    var owned = scene.save.WorldDelta.fromData(haxe.Json.parse('[{"id": "ekipten", "cell": 0, "components": {"sayac": {"hits": 2, "owner": "oyuncu"}}}, {"id": "dunyadan", "cell": 0, "components": {"sayac": {"hits": 3}}}]'),
      haxe.Json.parse('[{"id": "yikilan", "cell": 0}]'),
      haxe.Json.parse('[{"id": "o1", "cell": 0, "owner": "oyuncu", "scene": {"version": 1, "entities": [{"id": "o1", "name": "Kulübe", "components": []}]}}, {"id": "o2", "cell": 0, "owner": "", "scene": {"version": 1, "entities": [{"id": "o2", "name": "Sandık", "components": []}]}}]'));
    check(owned.isPlayerOwned("ekipten") && owned.isPlayerOwned("o1") && !owned.isPlayerOwned("dunyadan") && !owned.isPlayerOwned("o2"), "sahiplik: durumda owner ya da oyuncunun kurduğu");
    var part = owned.importPart();
    check(part.stateOf("ekipten") != null && part.stateOf("dunyadan") == null && part.isCreated("o1") && !part.isCreated("o2") && !part.isRemoved("yikilan"), "Import yalnızca oyuncununkileri taşımalı");
    // Hikâye ilerlemesi (story): çalışmış ödül tetikleyicisi sıfırlamadan sağ çıkar, ödül ikinci kez alınamaz.
    var story = scene.save.WorldDelta.fromData(haxe.Json.parse('[{"id": "odul", "cell": 0, "components": {"tetik": {"done": true, "story": true}}}, {"id": "npc", "cell": 0, "components": {"alan": {"x": 1}}}]'));
    check(story.isStory("odul") && !story.isStory("npc") && story.importPart().stateOf("odul") != null && story.importPart().stateOf("npc") == null, "Import hikâye ilerlemesini taşımalı");
    story.forgetCell(0);
    check(story.stateOf("odul") != null && story.stateOf("npc") == null, "bölge sıfırlama hikâye ilerlemesini korumalı");
    check(owned.stateOf("dunyadan") != null && owned.isRemoved("yikilan"), "Import asıl farka dokunmamalı");
    owned.forgetCell(0);
    check(owned.stateOf("ekipten") != null && owned.stateOf("dunyadan") == null && owned.isCreated("o1") && !owned.isRemoved("yikilan"), "bölge sıfırlama durumunda owner olanı korumalı");
    var ids = [for (_ in 0...3) scene.save.WorldDelta.newId(new scene.save.Random(9))];
    check(ids[0] == ids[1] && StringTools.startsWith(ids[0], "o") && ids[0].length == 16, 'kurulan nesne kimliği akıştan, aynı tohumla aynı: ${ids[0]}');
  }

  // Göç zinciri, içerik izi, dünya dizini.
  static function testSaveVersions() {
    var migrations = new scene.save.Migrations(3);
    migrations.add(1, "bir", sections -> sections.set("iz", [1]));
    migrations.add(2, "iki", sections -> {
      var trail : Array<Int> = sections.get("iz");
      trail.push(2);
    });
    var sections = new Map<String, Dynamic>();
    var applied = migrations.run(sections, 1);
    check(applied.length == 2 && applied[0] == "1 → 2: bir" && (sections.get("iz") : Array<Int>).join(",") == "1,2", 'göçler sırayla: $applied');
    equals(migrations.run(new Map(), 3).length, 0, "güncel kayıtta göç yok");
    check(try { migrations.run(new Map(), 4); false; } catch (e : Dynamic) Std.string(e).indexOf("yeni bir sürüm") >= 0, "yeni biçim reddedilmeli");
    var gap = new scene.save.Migrations(3);
    gap.add(2, "iki", _ -> {});
    check(try { gap.run(new Map(), 1); false; } catch (e : Dynamic) Std.string(e).indexOf("göçü yok") >= 0, "eksik adım hata vermeli");
    check(try { gap.add(3, "fazla", _ -> {}); false; } catch (e : Dynamic) true, "en son biçimden göç eklenemez");

    var world = new WorldData("world", 2, 1, 10, 2, []);
    var files = new Map<String, String>();
    function cellFile(ids : Array<String>, type : String) {
      var data = new SceneData(SceneFormat.VERSION);
      for (id in ids) {
        var item = new EntityData(id, "Ad " + id);
        item.components.push(new ComponentData(type));
        data.entities.push(item);
      }
      return SceneFormat.write(data);
    }
    files.set(world.path(WorldData.GLOBAL, WorldData.OBJECTS_SUFFIX), cellFile(["ekip1"], "sayac"));
    files.set(world.path(0, WorldData.OBJECTS_SUFFIX), cellFile(["t1", "t2"], "sayac"));
    files.set(world.path(1, WorldData.OBJECTS_SUFFIX), cellFile(["t3"], "baska"));
    files.set("data/esyalar.table.json", "{}");
    var read = path -> files.get(path);
    var before = scene.save.ContentPrint.compute(world, ["esyalar", "yok"], read);
    check(before.cells.exists("genel") && before.cells.exists("0") && before.tables.exists("esyalar") && !before.tables.exists("yok"), "içerik izi hücre ve tablo");
    var saved : Dynamic = haxe.Json.parse(haxe.Json.stringify(before));
    files.set(world.path(1, WorldData.OBJECTS_SUFFIX), cellFile(["t3", "t4"], "baska"));
    var diff = scene.save.ContentPrint.diff(saved, scene.save.ContentPrint.compute(world, ["esyalar"], read));
    check(diff != null && diff.cells.join(",") == "1" && diff.tables.length == 0, 'değişen hücre bulunmalı: ${haxe.Json.stringify(diff)}');
    check(scene.save.ContentPrint.diff(null, before) == null, "izi olmayan eski kayıt");
    var index = scene.save.WorldIndex.build(world, read, _ -> null);
    check(index.exists("ekip1") && index.exists("t4") && !index.exists("silinmis"), "dünya dizini");
    equals(index.candidates(0, "sayac").length, 2, "aynı hücrede aynı türden adaylar");
  }

  // Donmasız kayıt: hücre bölümü önbelleği, arka planda yazma, ana kare bütçesi.
  static function testSaveWriter() {
    function deltaOf(count : Int, cells : Int) {
      var items = [for (i in 0...count) {id: "n" + i, cell: i % cells, components: {sayac: {hits: i, x: i * 0.5, y: -i * 0.25}}}];
      return scene.save.WorldDelta.fromData(haxe.Json.parse(haxe.Json.stringify(items)));
    }
    var delta = deltaOf(9, 3);
    var sections = new scene.save.DeltaSections();
    var first = sections.sections(delta);
    equals([for (s in first) s.name].join(","), "hucre/0,hucre/1,hucre/2", "hücre bölümleri");
    delta.markRemoved(["n1"]);
    var second = sections.sections(delta);
    check(second[0].packed == first[0].packed && second[2].packed == first[2].packed && second[1].packed != first[1].packed, "yalnızca değişen hücre yeniden kodlanmalı");
    var decoded = scene.save.SaveFile.decode(scene.save.SaveFile.encodePacked(second));
    var cell1 : Dynamic = haxe.Json.parse(decoded.get("hucre/1").toString());
    check((cell1.silinenler : Array<Dynamic>).length == 1 && (cell1.durumlar : Array<Dynamic>).length == 2, "değişen hücrenin bölümü güncel");
    check(sections.sections(scene.save.WorldDelta.fromData([])).length == 0, "yeni fark deposunda önbellek baştan");

    var base = Sys.getEnv("TMPDIR");
    var dir = (base == null ? "/tmp" : base) + "/yazici_testi_" + Std.random(1000000000);
    sys.FileSystem.createDirectory(dir);
    var meta = scene.save.SaveFile.pack("meta", haxe.io.Bytes.ofString('{"format": 3}'));
    function job(path : String, n : Int, ?remove : Array<String>) : scene.save.SaveWriter.WriteJob
      return {path: path, sections: [meta, scene.save.SaveFile.pack("deneme", haxe.io.Bytes.ofString('{"n": $n}'))], remove: remove == null ? [] : remove, tag: n};
    var sync = new scene.save.SaveWriter(false);
    sync.submit(job('$dir/a.kayit', 1));
    var done = sync.poll();
    check(done.length == 1 && done[0].error == null && sync.pending == 0 && sys.FileSystem.exists('$dir/a.kayit'), "eşzamanlı yazıcı");
    sync.submit(job('$dir/b.kayit', 2, ['$dir/a.kayit', '$dir/yazilmaz.txt']));
    sync.poll();
    check(!sys.FileSystem.exists('$dir/a.kayit') && sys.FileSystem.exists('$dir/b.kayit'), "yazmadan önce silinecekler (yalnızca .kayit)");
    #if hl
    // Gerçek iş parçacığı: işler sırayla, aynı dosyaya son yazılan kalır.
    var threaded = new scene.save.SaveWriter(true);
    for (n in 3...7) threaded.submit(job('$dir/c.kayit', n));
    var all = threaded.flush();
    var last : Dynamic = haxe.Json.parse(scene.save.SaveFile.decode(sys.io.File.getBytes('$dir/c.kayit')).get("deneme").toString());
    check(all.length == 4 && Lambda.foreach(all, r -> r.error == null) && last.n == 6 && threaded.pending == 0, 'iş parçacığında sırayla yazma: ${last.n}');
    // Bütçe: 10.000 nesne durumu, 30 hücre; kayıt anında iki hücre değişmiş. Ana karede kodlama 16 ms altında.
    var big = deltaOf(10000, 30), cached = new scene.save.DeltaSections();
    var begun = haxe.Timer.stamp();
    var all = cached.sections(big);
    var full = (haxe.Timer.stamp() - begun) * 1000;
    big.touch(3);
    big.touch(4);
    begun = haxe.Timer.stamp();
    var again = cached.sections(big);
    var partial = (haxe.Timer.stamp() - begun) * 1000;
    Sys.println('  kayıt bütçesi: hepsi ${Math.round(full * 10) / 10} ms, iki hücre ${Math.round(partial * 10) / 10} ms (${again.length} bölüm)');
    check(again.length == 30 && partial < 16, 'ana kare bütçesi: iki hücre ${partial} ms');
    #end
    for (name in ["b.kayit", "c.kayit", "c.kayit.yedek"]) if (sys.FileSystem.exists('$dir/$name')) sys.FileSystem.deleteFile('$dir/$name');
    sys.FileSystem.deleteDirectory(dir);
  }

  // Optimizasyon motoru: en iyisi bilinen yapay işlevler.
  static function testTuner() {
    function module(?lockY : Float, ?sumLimit : Float) {
      var tunables : Array<scene.tune.TuneModule.Tunable> = [
        {id: "x", title: "X", min: 0, max: 10, step: 1, value: 0},
        {id: "y", title: "Y", min: 0, max: 10, step: 1, value: lockY != null ? lockY : 0, locked: lockY != null},
      ];
      var metrics : Array<scene.tune.TuneModule.Metric> = [
        {id: "uzaklik", title: "Uzaklık", group: scene.tune.TuneModule.QUALITY, goal: Min(100), weight: 1},
        {id: "toplam", title: "Toplam", group: scene.tune.TuneModule.PERFORMANCE, goal: Limit(null, sumLimit), weight: 0},
      ];
      return new scene.tune.TuneModule("deneme", "Deneme", tunables, metrics, (config, seed) -> {
        var x = config.get("x"), y = config.get("y");
        ["uzaklik" => (x - 3) * (x - 3) + (y - 7) * (y - 7) + (seed % 2) * 0.01, "toplam" => x + y];
      });
    }
    var grid = new scene.tune.Tuner(module());
    var found = grid.search(500);
    check(found.method.indexOf("kaba kuvvet") == 0 && found.best.config.get("x") == 3 && found.best.config.get("y") == 7 && found.evaluated == 121, 'kaba kuvvet en iyiyi bulmalı: ${found.best.config}');
    var sampled = new scene.tune.Tuner(module());
    var near = sampled.search(60);
    check(near.method.indexOf("rastgele") == 0 && near.best.config.get("x") == 3 && near.best.config.get("y") == 7 && near.evaluated <= 61, 'örnekleme ve yerel iyileştirme: ${near.best.config} (${near.evaluated})');
    var again = new scene.tune.Tuner(module()).search(60);
    check(sampled.keyOf(again.best.config) == sampled.keyOf(near.best.config) && again.evaluated == near.evaluated, "aynı tohum aynı arama");
    var limited = new scene.tune.Tuner(module(null, 9)).search(500);
    check(limited.best.valid && limited.best.config.get("x") + limited.best.config.get("y") <= 9 && limited.best.score > 0.98, 'sert sınır elemeli: ${limited.best.config}');
    check(limited.baseline.valid && limited.baseline.config.get("x") == 0, "başlangıç (bugünkü değerler) değerlendirilir");
    var locked = new scene.tune.Tuner(module(5)).search(500);
    check(locked.best.config.get("y") == 5 && locked.best.config.get("x") == 3 && locked.evaluated == 11, 'kilitli ayar değişmemeli: ${locked.best.config}');
    var report = scene.tune.TuneReport.write(grid, found, "deneme");
    check(report.indexOf("**değişti**") > 0 && report.indexOf("Uzaklık") > 0 && report.indexOf("doğrulama") > 0, "rapor");
    var lockedReport = scene.tune.TuneReport.write(new scene.tune.Tuner(module(5)), locked, "deneme");
    check(lockedReport.indexOf("Kilitli ayarların etkisi") > 0, "kilitli ayarın etkisi raporda");
    check(found.front.length >= 1 && found.front[0].valid, "kalite ve performans sınırı");
    // Dışarıdan tohum çalıştırıcısı (işçi süreç havuzu gibi): tohumlar ters sırada çalışsa da sonuç tohum sırasıyla.
    var outside = new scene.tune.Tuner(module());
    var plain = module();
    outside.seedRunner = (config, seeds) -> {
      var reversed = seeds.copy();
      reversed.reverse();
      var done = [for (seed in reversed) seed => plain.run(config, seed)];
      [for (seed in seeds) done.get(seed)];
    };
    var same = outside.search(60);
    check(outside.keyOf(same.best.config) == sampled.keyOf(near.best.config) && same.best.score == near.best.score && same.evaluated == near.evaluated, "dışarıdan çalıştırıcıyla aynı sonuç");
  }

  static function testSaveFiles() {
    var sections = [scene.save.SaveFile.section("meta", {format: 1, name: "Sefer ş"}), {name: "bos", data: haxe.io.Bytes.alloc(0)}];
    var bytes = scene.save.SaveFile.encode(sections);
    var read = scene.save.SaveFile.decode(bytes);
    equals(scene.save.SaveFile.json(read, "meta").name, "Sefer ş", "bölüm okunmalı");
    equals(read.get("bos").length, 0, "boş bölüm okunmalı");
    var broken = bytes.sub(0, bytes.length);
    broken.set(10, broken.get(10) ^ 0xFF);
    check(try { scene.save.SaveFile.decode(broken); false; } catch (e : Dynamic) Std.string(e).indexOf("bozuk") >= 0, "bozuk dosya fark edilmeli");

    // Geçici klasör: yalnızca bu testin yazdığı dosyalar silinir.
    var base = Sys.getEnv("TMPDIR");
    var dir = (base == null ? "/tmp" : base) + "/kayit_testi_" + Std.random(1000000000);
    var slots = new scene.save.SaveSlots(dir);
    equals(slots.campaigns().length, 0, "klasör yokken sefer yok");
    var campaign = slots.createCampaign("Deneme", true, "0.1");
    equals(slots.campaigns()[0].ironman, true, "sefer okunmalı");
    var quick = slots.pathFor(campaign.id, scene.save.SaveSlots.QUICK);
    scene.save.SaveFile.writeSafely(quick, bytes);
    scene.save.SaveFile.writeSafely(quick, scene.save.SaveFile.encode([scene.save.SaveFile.section("meta", {format: 1, name: "ikinci"})]));
    check(sys.FileSystem.exists(quick + scene.save.SaveFile.BACKUP_SUFFIX), "eski kayıt yedek olmalı");
    check(!sys.FileSystem.exists(quick + scene.save.SaveFile.TEMP_SUFFIX), "geçici dosya kalmamalı");
    sys.io.File.saveBytes(quick, broken);
    var safe = scene.save.SaveFile.readSafely(quick);
    check(safe.fromBackup && scene.save.SaveFile.json(safe.sections, "meta").name == "Sefer ş", "bozuksa yedek açılmalı");
    var autos = [for (i in 0...scene.save.SaveSlots.AUTO_COUNT + 1) {
      var path = slots.pathFor(campaign.id, scene.save.SaveSlots.AUTO);
      sys.io.File.saveBytes(path, bytes);
      path;
    }];
    equals(autos[scene.save.SaveSlots.AUTO_COUNT], autos[0], "yuvalar dolunca otomatik kayıt en eskinin yerine");
    // Sefer araçları: en yeni kayıt, boyut, bitmiş sefer, silme, başka kökten kopya.
    equals(slots.latestOverall() == null ? "" : slots.latestOverall().campaign, campaign.id, "devam et en yeni kaydı bulmalı");
    check(slots.campaignSize(campaign.id) > 0 && slots.campaignSize("yok") == 0, "sefer boyutu");
    var manualPath = slots.pathFor(campaign.id, scene.save.SaveSlots.MANUAL);
    sys.io.File.saveBytes(manualPath, bytes);
    var manual = slots.oldestManual(campaign.id);
    check(manual != null && manual.path == manualPath, "en eski elle kayıt");
    slots.deleteSave(manual);
    check(!sys.FileSystem.exists(manualPath) && slots.oldestManual(campaign.id) == null, "elle kayıt silinmeli");
    check(try { slots.deleteSave({path: dir + "/baska.txt", kind: "elle", modified: 0, campaign: campaign.id}); false; } catch (e : Dynamic) true, "sefer dışı yol silinmemeli");
    var other = new scene.save.SaveSlots(dir + "_hesap");
    equals(other.missingFrom(slots).length, 1, "hesapta olmayan sefer");
    check(other.copyCampaign(slots, campaign.id) && other.saves(campaign.id).length == slots.saves(campaign.id).length, "sefer kopyalanmalı");
    check(!sys.FileSystem.exists('${other.root}/${campaign.id}/${scene.save.SaveSlots.QUICK}.kayit${scene.save.SaveFile.BACKUP_SUFFIX}'), "yedek kopyalanmamalı");
    check(!other.copyCampaign(slots, campaign.id) && other.missingFrom(slots).length == 0, "ikinci kopya olmamalı");
    var ended = slots.campaign(campaign.id);
    ended.ended = true;
    ended.result = "Ekip tükendi";
    slots.updateCampaign(ended);
    check(slots.campaign(campaign.id).ended == true && slots.latestOverall() == null, "bitmiş sefer devam edilmez");
    for (name in sys.FileSystem.readDirectory('${other.root}/${campaign.id}')) sys.FileSystem.deleteFile('${other.root}/${campaign.id}/$name');
    sys.FileSystem.deleteDirectory('${other.root}/${campaign.id}');
    sys.FileSystem.deleteDirectory(other.root);
    equals(slots.saves(campaign.id).filter(e -> e.kind == scene.save.SaveSlots.AUTO).length, 5, "beş otomatik yuva");
    equals(scene.save.SaveSlots.kindOf("elle_2026-11-03_120000.kayit"), scene.save.SaveSlots.MANUAL, "elle kayıt türü");
    equals(scene.save.SaveSlots.kindOf("cikis.kayit"), scene.save.SaveSlots.EXIT, "çıkış kaydı türü");
    for (name in sys.FileSystem.readDirectory('$dir/${campaign.id}')) sys.FileSystem.deleteFile('$dir/${campaign.id}/$name');
    sys.FileSystem.deleteDirectory('$dir/${campaign.id}');
    sys.FileSystem.deleteDirectory(dir);
  }

  static function testWorldDelta() {
    var world = new WorldData("world", 5, 1, 10, 2, []);
    var files = new Map<String, String>();
    for (cell in world.cells()) {
      var data = new SceneData(SceneFormat.VERSION);
      var item = new EntityData("n" + cell, "Sayaç " + cell);
      item.components.push(new ComponentData("sayac"));
      data.entities.push(item);
      files.set(world.path(cell, WorldData.OBJECTS_SUFFIX), SceneFormat.write(data));
    }
    var types = registry();
    types.register(Counter);
    var game = new SceneInstance(types, Game, new Object());
    var delta = new scene.save.WorldDelta();
    game.delta = delta;
    var streamer = new CellStreamer(new WorldState(world, path -> files.get(path)), game, true);
    streamer.objectRadius = 0;
    streamer.start(world.cellLeft(0) + 1, 0);
    game.start();
    var counter = game.find("n0").getComponent(Counter);
    counter.hits = 3;
    streamer.update(world.cellLeft(4) + 1, 0);
    check(game.find("n0") == null, "uzak hücre kapanmalı");
    equals(delta.size(), 1, "kapanan hücrenin farkı alınmalı");
    equals(delta.cellOf("n0"), 0, "farkın hücresi bilinmeli");
    equals(delta.stateOf("n4"), null, "değişmeyen nesnenin farkı olmamalı");
    streamer.update(world.cellLeft(0) + 1, 0);
    var back = game.find("n0").getComponent(Counter);
    check(back != counter, "hücre yeniden kurulmalı");
    equals(back.hits, 3, "durum geri gelmeli");
    equals(back.seenAtStart, 3, "durum onStart'tan önce yüklenmeli");

    var text = haxe.Json.stringify(delta.toData());
    var copy = scene.save.WorldDelta.fromData(haxe.Json.parse(text));
    equals(haxe.Json.stringify(copy.toData()), text, "fark dosyaya yazılıp aynen okunmalı");
    equals(copy.cellOf("n0"), 0, "hücre bilgisi okunmalı");

    back.hits = 0;
    streamer.update(world.cellLeft(4) + 1, 0);
    equals(delta.size(), 0, "farkı kalmayan nesne listeden düşmeli");
    back = null;
    streamer.update(world.cellLeft(0) + 1, 0);
    game.find("n0").getComponent(Counter).hits = 5;
    streamer.update(world.cellLeft(4) + 1, 0);
    delta.forgetCell(0);
    equals(delta.size(), 0, "bölge sıfırlanınca farkı atılmalı");
    streamer.update(world.cellLeft(0) + 1, 0);
    equals(game.find("n0").getComponent(Counter).hits, 0, "sıfırlanan bölge tasarlanmış haliyle gelmeli");

    // Dünyada artık olmayan nesnenin farkı (tasarımcı sildi) kayıtlar boyunca korunur: sonradan bir eşleme kurtarabilir.
    var orphan = scene.save.WorldDelta.fromData(haxe.Json.parse('[{"id": "silinmis", "cell": 2, "components": {"sayac": {"hits": 7}}}]'));
    game.delta = orphan;
    orphan.captureAll(game.entities);
    var kept : Dynamic = orphan.stateOf("silinmis");
    equals(kept == null ? -1 : kept.sayac.hits, 7, "yetim fark kayıtta kalmalı");
    equals(scene.save.WorldDelta.fromData(haxe.Json.parse(haxe.Json.stringify(orphan.toData()))).cellOf("silinmis"), 2, "yetim fark dosyaya da yazılmalı");
    equals(orphan.remap(["silinmis" => "yenisi"]), 1, "eşleme farkı taşımalı");
    var moved : Dynamic = orphan.stateOf("yenisi");
    check(moved != null && moved.sayac.hits == 7 && orphan.stateOf("silinmis") == null && orphan.cellOf("yenisi") == 2, "eski kimliğin durumu ve hücresi yeniye geçmeli");
    // İkinci yayında yenisi de silinip başkasına eşlendi: ilk sürümden kalan kayıt zincirin sonuna gider; döngü takılmaz.
    var first = scene.save.WorldDelta.fromData(haxe.Json.parse('[{"id": "a", "cell": 2, "components": {"sayac": {"hits": 3}}}]'));
    equals(first.remap(["b" => "c", "a" => "b"]), 1, "zincirli eşleme");
    var chained : Dynamic = first.stateOf("c");
    check(chained != null && chained.sayac.hits == 3 && first.stateOf("a") == null && first.stateOf("b") == null, "A→B→C: A'nın durumu C'ye");
    var loop = scene.save.WorldDelta.fromData(haxe.Json.parse('[{"id": "x", "cell": 2, "components": {"sayac": {"hits": 1}}}]'));
    loop.remap(["x" => "y", "y" => "x"]);
    check(true, "döngülü eşleme takılmamalı");
  }

  static function testStreaming() {
    var world = new WorldData("world", 5, 1, 10, 2, []);
    var files = new Map<String, String>();
    function objects(cell : Int, id : String) {
      var data = new SceneData(SceneFormat.VERSION);
      var item = new EntityData(id, id);
      item.components.push(new ComponentData("crate"));
      data.entities.push(item);
      files.set(world.path(cell, WorldData.OBJECTS_SUFFIX), SceneFormat.write(data));
    }
    objects(WorldData.GLOBAL, "ekip");
    for (cell in world.cells()) objects(cell, "n" + cell);
    var state = new WorldState(world, path -> files.get(path));
    var scene = newScene(Game);
    var streamer = new CellStreamer(state, scene, true);
    streamer.objectRadius = 1;
    streamer.terrainRadius = 2;
    streamer.start(world.cellLeft(0) + 1, 0);
    equals(scene.entities.length, 3, "genel ve iki hücre yüklü");
    check(scene.find("ekip") != null, "genel nesne yüklü");
    check(streamer.isLoaded(1) && !streamer.isLoaded(2), "yalnızca yakın hücreler");
    check(state.terrain.get(2) != null && state.terrain.get(3) == null, "arazi daha geniş halkada");
    scene.start();

    streamer.update(world.cellLeft(2) + 1, 0);
    check(streamer.isLoaded(0), "bir hücre geriden boşalır, sınırda gidip gelmek hücreyi kapatmaz");
    equals(streamer.loadedCount(), 3, "karede tek hücre açılır");
    streamer.update(world.cellLeft(2) + 1, 0);
    equals(streamer.loadedCount(), 4, "sıradaki hücre sonraki karede");
    check(scene.find("n3") != null, "yeni hücre gelmeli");
    streamer.update(world.cellLeft(3) + 1, 0);
    check(!streamer.isLoaded(0), "uzaklaşan hücre boşalmalı");
    check(scene.find("n0") == null, "boşalan hücrenin nesnesi gitmeli");
    check(scene.find("ekip") != null, "genel nesne hücreyle gitmez");
    check(state.terrain.get(1) != null, "yakın arazi kalır");
    streamer.update(world.cellLeft(4) + 1, 0);
    check(state.terrain.get(1) == null, "uzak arazi gider");
    streamer.update(9999, 0);
    check(scene.find("ekip") != null, "dünya dışına çıkmak bir şey bozmamalı");

    // Hücresinden çıkıp oyuncunun yanına gelen kervan hücreyle silinmez
    var types = registry();
    types.register(Traveller);
    var moving = new SceneData(SceneFormat.VERSION);
    var item = new EntityData("kervan", "Kervan");
    item.components.push(new ComponentData("traveller"));
    moving.entities.push(item);
    files.set(world.path(0, WorldData.OBJECTS_SUFFIX), SceneFormat.write(moving));
    var held = new SceneInstance(types, Game, new Object());
    var follow = new CellStreamer(new WorldState(world, path -> files.get(path)), held, true);
    follow.objectRadius = 0;
    follow.start(world.cellLeft(0) + 1, 0);
    held.start();
    var traveller = held.find("kervan").getComponent(Traveller);
    traveller.at = world.cellLeft(4) + 1;
    follow.update(world.cellLeft(4) + 1, 0);
    check(follow.isLoaded(0), "kervan kameranın yanındayken hücresi boşalmamalı");
    check(held.find("kervan") != null, "takip edilen kervan silinmemeli");
    follow.update(world.cellLeft(4) + 1, 0);
    traveller.at = world.cellLeft(0) + 1;
    follow.update(world.cellLeft(4) + 1, 0);
    check(!follow.isLoaded(0), "kervan uzaklaşınca hücre boşalmalı");
    check(held.find("kervan") == null, "uzaktaki kervan gitmeli");

    // Tek sahne açıkken nesne yüklenmez
    var plain = newScene(Game);
    var terrainOnly = new CellStreamer(new WorldState(world, path -> null), plain, false);
    terrainOnly.start(0, 0);
    equals(plain.entities.length, 0, "tek sahnede hücre nesnesi yok");
  }

  static function testEntityLookup() {
    var scene = newScene();
    var parent = scene.createEntity("Üst", "a");
    var child = scene.createEntity("Alt", "b");
    child.setParent(parent);
    equals(child.root, parent, "kök bulunmalı");
    equals(parent.root, parent, "kök kendisi");
    equals(scene.find("b"), child, "kimlikle bulunmalı");
    var detached = scene.detach(parent);
    equals(scene.find("b"), null, "çıkarılan bulunmamalı");
    scene.attach(detached);
    equals(scene.find("b"), child, "geri gelen bulunmalı");
    scene.destroyEntity(parent);
    equals(scene.find("a"), null, "silinen bulunmamalı");
    equals(scene.find("b"), null, "silinen alt nesne bulunmamalı");

    var world = scene.createEntity("Kök", "c");
    equals(scene.toDataWhere(root -> root == world).entities.length, 1, "koşula uyan kök");
    equals(scene.toDataWhere(root -> root != world).entities.length, 0, "koşula uymayan kök");
  }

  // Hücre boşaltmak yalnızca o hücrenin adımlarını düşürür.
  static function testForgetCommands() {
    var scene = newScene();
    var a = scene.createEntity("A", "a"), b = scene.createEntity("B", "b");
    var stack = new CommandStack();
    stack.execute(new SetNameCommand(a, "A", "A1"));
    stack.execute(new SetNameCommand(b, "B", "B1"));
    stack.execute(new SetNameCommand(a, "A1", "A2"));
    stack.execute(new SetNameCommand(b, "B1", "B2"));
    stack.undo();
    equals(stack.undoCount, 3, "üç adım");
    equals(stack.redoCount, 1, "bir yineleme");
    stack.forget(command -> command.touched().indexOf(a) >= 0);
    equals(stack.undoCount, 1, "A adımları düşmeli");
    equals(stack.redoCount, 1, "yineleme kalmalı");
    stack.redo();
    equals(b.name, "B2", "kalan yineleme çalışmalı");
    stack.undo();
    stack.undo();
    equals(b.name, "B", "kalan adım geri alınmalı");
    equals(a.name, "A2", "düşen adım a'ya dokunmamalı");
    check(!stack.canUndo, "geçmiş boşalmalı");

    var clean = new CommandStack();
    clean.execute(new SetNameCommand(a, "A2", "A3"));
    clean.markSaved();
    clean.forget(_ -> true);
    check(!clean.isDirty, "kayıtlı geçmişi temizlemek kirletmemeli");

    var group = new GroupCommand("Grup", [new SetNameCommand(a, "x", "y"), new SetNameCommand(b, "x", "y")]);
    equals(group.touched().length, 2, "grup üyelerini bildirmeli");
  }

  static function brushWorld(editable : Int->Bool, ?calls : Array<Array<Int>>) {
    var world = new WorldData("world", 2, 2, 40, 4, [{id: "a", title: "A", color: 0}, {id: "b", title: "B", color: 1}]);
    var state = new WorldState(world, _ -> null);
    state.view = new NullView();
    state.loadAllTerrain();
    return {state: state, brush: new WorldBrush(state, editable, cell -> editable(cell) && !state.terrain.get(cell).hasCoverage(), (terrain, scatter) -> if (calls != null) calls.push(terrain))};
  }

  static function testBrushes() {
    var test = brushWorld(_ -> true);
    var state = test.state, brush = test.brush;
    brush.tool = Raise;
    brush.radius = 15;
    brush.begin(0, 0);
    brush.apply(0, 0, 0.5);
    var command = brush.finish();
    var peak = state.terrain.heightAt(0, 0);
    check(peak > 0, 'yükselmeli: $peak');
    check(Math.abs(state.terrain.heightAt(5, 5) - peak) < peak, "uzak köşe daha az yükselir");
    equals(state.terrain.heightAt(25, 25), 0, "yarıçap dışı değişmez");
    // Kesişimdeki köşe dört hücrede de aynı
    for (cell in 0...4) {
      var data = state.terrain.get(cell);
      var x = cell % 2 == 0 ? 4 : 0, y = cell < 2 ? 4 : 0;
      equals(data.height(x, y), peak, 'ortak köşe hücre $cell');
    }

    var stack = new CommandStack();
    stack.execute(command);
    equals(state.terrain.heightAt(0, 0), peak, "komut aynı sonucu vermeli");
    stack.undo();
    equals(state.terrain.heightAt(0, 0), 0, "geri alınmalı");
    stack.redo();
    equals(state.terrain.heightAt(0, 0), peak, "yinelenmeli");

    brush.tool = Lower;
    brush.begin(0, 0);
    brush.apply(0, 0, 0.5);
    brush.finish();
    check(Math.abs(state.terrain.heightAt(0, 0)) < 0.001, 'alçalmalı: ${state.terrain.heightAt(0, 0)}');

    brush.tool = Raise;
    brush.begin(0, 0);
    brush.apply(0, 0, 1);
    brush.finish();
    brush.tool = Flatten;
    brush.strength = 1;
    brush.radius = 30;
    brush.begin(0, 0);
    for (i in 0...100) brush.apply(0, 0, 0.1);
    brush.finish();
    var center = state.terrain.heightAt(0, 0);
    check(Math.abs(state.terrain.vertexHeight(5, 4) - center) < 0.5, 'düzleşmeli: ${state.terrain.vertexHeight(5, 4)} / $center');

    var rough = brushWorld(_ -> true);
    rough.state.terrain.setVertexHeight(4, 4, 10);
    rough.brush.tool = Smooth;
    rough.brush.strength = 1;
    rough.brush.begin(0, 0);
    for (i in 0...10) rough.brush.apply(0, 0, 0.1);
    rough.brush.finish();
    check(rough.state.terrain.vertexHeight(4, 4) < 5, 'yumuşamalı: ${rough.state.terrain.vertexHeight(4, 4)}');
    check(rough.state.terrain.vertexHeight(5, 4) > 0, "komşu yükselmeli");
  }

  // Yüklü olmayan hücreye dokunan kenar değişmez: iki kişi komşu hücrede çalışınca çakışmaz.
  static function testBrushLockedEdges() {
    var calls = [];
    var test = brushWorld(cell -> cell == 0, calls);
    var state = test.state, brush = test.brush;
    var other = state.terrain.get(1).write();
    brush.tool = Raise;
    brush.radius = 60;
    brush.begin(-20, -20);
    brush.apply(-20, -20, 1);
    var command = brush.finish();
    check(state.terrain.get(0).height(2, 2) > 0, "yüklü hücre değişmeli");
    equals(state.terrain.get(0).height(4, 2), 0, "komşusu yüklü olmayan kenar kilitli");
    equals(state.terrain.get(0).height(2, 4), 0, "üst kenar kilitli");
    equals(state.terrain.get(1).write(), other, "yüklü olmayan hücre değişmemeli");
    check(command.touchesCell(0), "komut kendi hücresini bildirmeli");
    check(!command.touchesCell(1), "komut başka hücreyi bildirmemeli");

    var paint = brushWorld(cell -> cell == 0);
    paint.brush.tool = Paint;
    paint.brush.radius = 30;
    paint.brush.layer = 1;
    paint.brush.begin(0, 0);
    paint.brush.apply(0, 0, 0.1);
    var painted = paint.brush.finish();
    equals(paint.state.terrain.get(0).layer(3, 3), 1, "boya uygulanmalı");
    equals(paint.state.terrain.get(1).layer(0, 3), 0, "yüklü olmayan hücre boyanmamalı");
    var stack = new CommandStack();
    stack.execute(painted);
    stack.undo();
    equals(paint.state.terrain.get(0).layer(3, 3), 0, "boya geri alınmalı");

    var heights = brushWorld(cell -> cell == 0);
    var map = heights.brush.replaceHeights((u, v) -> 50, "Yükseklik haritası");
    equals(heights.state.terrain.get(0).height(1, 1), 50, "yükseklik haritası uygulanmalı");
    equals(heights.state.terrain.get(0).height(4, 1), 0, "kilitli kenar korunmalı");
    equals(heights.state.terrain.get(3).height(1, 1), 0, "yüklü olmayan hücre korunmalı");
    var undo = new CommandStack();
    undo.execute(map);
    undo.undo();
    equals(heights.state.terrain.get(0).height(1, 1), 0, "yükseklik haritası geri alınmalı");
  }

  static function testScatterBrush() {
    var test = brushWorld(cell -> cell != 1);
    var state = test.state, brush = test.brush;
    brush.tool = Scatter;
    brush.scatterType = "rock";
    brush.radius = 15;
    brush.density = 0.1;
    brush.begin(-20, -20);
    brush.apply(-20, -20, 0.1);
    brush.apply(-20, -20, 0.1);
    var command = brush.finish();
    var items = state.scatter.get(0).items;
    check(items.length > 0, "saçılmalı");
    for (item in items) {
      check(item.scale >= brush.minScale && item.scale <= brush.maxScale, 'ölçek aralıkta: ${item.scale}');
      equals(item.type, "rock", "tür");
    }
    var count = items.length;
    var stack = new CommandStack();
    stack.execute(command);
    stack.undo();
    equals(state.scatter.get(0).items.length, 0, "saçma geri alınmalı");
    stack.redo();
    equals(state.scatter.get(0).items.length, count, "saçma yinelenmeli");

    // Yüklü olmayan hücreye saçılmaz
    brush.begin(20, -20);
    brush.apply(20, -20, 0.1);
    brush.finish();
    equals(state.scatter.get(1), null, "yüklü olmayan hücre değişmemeli");

    state.scatter.get(0).items.push({type: "tree", x: -20, y: -20, rotation: 0, scale: 1});
    brush.tool = Erase;
    brush.begin(-20, -20);
    brush.apply(-20, -20, 0.1);
    var erased = brush.finish();
    equals(state.scatter.get(0).items.filter(item -> item.type == "rock").length, 0, "seçili tür silinmeli");
    equals(state.scatter.get(0).items.length, 1, "başka tür kalmalı");
    stack.execute(erased);
    stack.undo();
    equals(state.scatter.get(0).items.length, count + 1, "silme geri alınmalı");
  }

  // Yol ağı için iki hücrelik dünya: ortada kapısı olan duvar.
  static function navWorld(gap : Bool) {
    var world = new WorldData("world", 2, 1, 20, 2, []);
    world.navResolution = 10;
    var files = new Map<String, String>();
    var state = new WorldState(world, path -> files.get(path));
    state.loadAllTerrain();
    var shapes = [NavShapes.box2(0, gap ? -6 : 0, 1, gap ? 4 : 10)];
    for (cell in world.cells()) files.set(world.path(cell, WorldData.NAV_SUFFIX), NavBaker.bake(cell, world, state.terrain, shapes).write());
    return {world: world, state: state, files: files, nav: new NavWorld(state)};
  }

  static function testNav() {
    var cell = new NavCell(4);
    cell.block(1, 0);
    cell.block(2, 0);
    cell.block(0, 3);
    var text = cell.write();
    var read = NavCell.read(text);
    check(read.isBlocked(1, 0) && read.isBlocked(0, 3) && !read.isBlocked(3, 0), "yol ağı okunmalı");
    equals(read.write(), text, "yol ağı dosyası kararlı");
    check(text.indexOf('"1,2,1"') >= 0, 'satır uzunluklarla yazılmalı: $text');

    // Düz arazide yol düz çizgidir
    var open = navWorld(true);
    var path = open.nav.findPath(-15, 8, 15, 8);
    equals(path.length, 1, 'engelsiz yol tek parça: ${path.length}');
    equals(path[0].x, 15, "hedefe gitmeli");

    // Duvarın kapısından geçer
    var around = open.nav.findPath(-15, -6, 15, -6);
    check(around.length > 1, 'duvarı dolaşmalı: $around');
    var lastY = -6.;
    var ax = -15., ay = -6.;
    for (point in around) {
      var steps = 40;
      for (i in 0...steps) {
        var x = ax + (point.x - ax) * i / steps, y = ay + (point.y - ay) * i / steps;
        check(open.nav.isWalkable(x, y), 'yol engelden geçmemeli: $x, $y');
      }
      ax = point.x;
      ay = point.y;
    }
    equals(around[around.length - 1].x, 15, "hedefe varmalı");
    equals(around[around.length - 1].y, -6, "hedefe varmalı");

    // Kapalı duvar: yol yok, en yakın yere gider
    var closed = navWorld(false);
    var blocked = closed.nav.findPath(-15, 0, 15, 0);
    var end = blocked[blocked.length - 1];
    check(end.x < 0, 'duvarı geçmemeli: ${end.x}');
    check(end.x > -5, 'duvara en yakın yere gitmeli: ${end.x}');

    // Ulaşılamayan hedef: iki ayrı başlangıçtan aynı yere varılır (hedefe en yakın ulaşılabilir düğüm; Anıt 1'in yaylası,
    // yakın ve uzak katman farklı yerlere varıyordu), arama bütün bölgeyi açmaz, varılmadığı söylenir.
    var other = closed.nav.findPath(-15, 8, 15, 0);
    var otherEnd = other[other.length - 1];
    check(Math.abs(otherEnd.x - end.x) < 1e-6 && Math.abs(otherEnd.y - end.y) < 1e-6, 'ulaşılamayan hedefte iki başlangıç aynı yere: (${end.x}, ${end.y}) / (${otherEnd.x}, ${otherEnd.y})');
    check(!closed.nav.lastReached, "ulaşılamayan hedef: varılmadı");
    Sys.println('  yol ağı, ulaşılamayan hedef: (${end.x}, ${end.y}) ve (${otherEnd.x}, ${otherEnd.y}), ${closed.nav.lastExpansions} düğüm');
    check(Math.abs(end.y) < 2.5, 'hedefe en yakın ulaşılabilir yer hedefin hizasında: ${end.y}');

    // Başlangıç engelin içindeyse en yakın açık yerden çıkar
    check(closed.nav.findPath(0, 0, -15, 0).length >= 1, "engel içinden çıkabilmeli");

    // Dosya yoksa hücre yürünebilir sayılır
    var world = new WorldData("world", 2, 1, 20, 2, []);
    world.navResolution = 10;
    var state = new WorldState(world, _ -> null);
    equals(new NavWorld(state).findPath(-15, 0, 15, 0).length, 1, "yol ağı yoksa düz gider");

    // Dik yamaç yürünmez
    var slope = new WorldData("world", 1, 1, 20, 2, []);
    slope.navResolution = 10;
    var hill = new WorldTerrain(slope);
    var terrain = TerrainCell.flat(2);
    terrain.setHeight(2, 0, 90);
    terrain.setHeight(2, 1, 90);
    terrain.setHeight(2, 2, 90);
    hill.set(0, terrain);
    var baked = NavBaker.bake(0, slope, hill, []);
    check(baked.isBlocked(8, 5), "dik yamaç kapalı");
    equals(NavBaker.bake(0, slope, hill, []).write(), baked.write(), "aynı girdi aynı dosya");

    var round = NavBaker.bake(0, slope, new WorldTerrain(slope), [NavShapes.circle(0, 0, 3)]);
    check(round.isBlocked(5, 5), "yuvarlak engel kapalı");
    check(!round.isBlocked(0, 0), "uzak düğüm açık");
  }

  static function testEnvironment() {
    var environment = new EnvironmentData();
    environment.hour = 19.5;
    environment.fogColor = 0x102030;
    var text = environment.write();
    var read = EnvironmentData.read(text);
    equals(read.hour, 19.5, "saat okunmalı");
    equals(read.fogColor, 0x102030, "renk okunmalı");
    equals(read.write(), text, "ortam dosyası kararlı");
    var copy = read.clone();
    copy.applyPreset({id: "a", title: "A", sun: 0.5, fogStart: 1, fogEnd: 2, fogColor: 3});
    equals(copy.sun, 0.5, "hazır ayar uygulanmalı");
    equals(copy.hour, 19.5, "hazır ayar saati değiştirmez");
    equals(read.sun, environment.sun, "kopya aslını değiştirmez");
  }

  static function modelAt(x : Float, width : Float, rotation = 0.) : TerrainModel {
    return {source: "assets/terrain/a.fbx", x: x, y: 0, base: 10, width: width, rotation: rotation, heightScale: 2, tiling: 4,
      originX: 1, originY: 2, originZ: 3, originWidth: 2};
  }

  static function testTerrainModels() {
    // Yerleşim: merkeze taşı, ölçekle, döndür
    var model = modelAt(100, 20);
    var point = TerrainModels.place(model, 2, 2, 4);
    equals(point[0], 110, "genişliğe göre ölçek");
    equals(point[1], 0, "merkez y");
    equals(point[2], 30, "taban ve dikey çarpan");
    var turned = TerrainModels.place(modelAt(0, 20, 90), 2, 2, 3);
    check(Math.abs(turned[0]) < 1e-9 && Math.abs(turned[1] - 10) < 1e-9, 'dönüş: $turned');

    // Dünya dosyası modeli ve eğimi taşır
    var world = new WorldData("world", 2, 1, 40, 4, []);
    world.maxSlope = 60;
    world.terrainModels = [model];
    var text = world.write();
    var read = WorldData.read(text, "world");
    equals(read.maxSlope, 60, "eğim okunmalı");
    equals(read.terrainModels.length, 1, "model okunmalı");
    equals(read.terrainModels[0].tiling, 4, "doku tekrarı okunmalı");
    equals(read.write(), text, "dünya dosyası kararlı");
    equals(new WorldData("world", 2, 1, 40, 4, []).write().indexOf('"terrainModels": []') >= 0, true, "boş liste tek satır");

    // Yeniden örnekleme
    var cell = TerrainCell.flat(4, 2);
    cell.setHeight(4, 4, 10);
    cell.setLayer(3, 3, 2);
    var fine = cell.resample(8);
    equals(fine.resolution, 8, "yeni çözünürlük");
    equals(fine.height(8, 8), 10, "köşe korunmalı");
    equals(fine.height(7, 7), 4, "ara değer çift doğrusal");
    equals(fine.layer(7, 7), 2, "boya en yakın kareden");
    equals(fine.resample(4).height(4, 4), 10, "geri örnekleme");

    // Hücre başına çözünürlük: ince hücre de doğru yüksekliği verir
    var terrain = new WorldTerrain(world);
    terrain.set(0, TerrainCell.flat(4, 1));
    terrain.set(1, fine);
    equals(terrain.heightAt(-10, 0), 1, "kaba hücre");
    check(Math.abs(terrain.heightAt(39.99, 19.99) - 10) < 0.1, 'ince hücrenin köşesi: ${terrain.heightAt(39.99, 19.99)}');
    equals(terrain.vertexHeight(4, 0), 1, "fırça köşesi dünya çözünürlüğündeki hücreden okunur");

    // Modelden yükseklik: hücrenin sol yarısını kaplayan z = 5 düzlemi
    var flat = new WorldData("world", 1, 1, 90, 2, []);
    var base = new WorldTerrain(flat);
    base.set(0, TerrainCell.flat(2, 1));
    var positions = [-45., -45, 5, 0, -45, 5, 0, 45, 5, -45, 45, 5];
    var baked = TerrainModelBaker.bake(flat, base.get, positions, [0, 1, 2, 0, 2, 3]).get(0);
    equals(baked.resolution, TerrainModelBaker.RESOLUTION, "model hücresi ince örneklenir");
    equals(baked.height(0, 0), 5, "model altında model yüksekliği");
    equals(baked.height(90, 0), 1, "model dışında eski yükseklik");
    equals(baked.layer(10, 10), TerrainCell.COVERED, "model altındaki kareyi model çizer");
    equals(baked.layer(80, 10), 0, "model dışındaki kareyi oyun çizer");
    check(baked.hasCoverage(), "kaplama bilinmeli");
    var under = new WorldTerrain(flat);
    under.set(0, baked);
    equals(under.heightAt(-30, 0), 5, "model üstünde yükseklik");

    // Model altındaki hücreye fırça dokunmaz, dağıtma çalışır
    var test = brushWorld(_ -> true);
    var covered = test.state.terrain.get(0).resample(TerrainModelBaker.RESOLUTION);
    covered.setLayer(0, 0, TerrainCell.COVERED);
    test.state.terrain.set(0, covered);
    test.brush.tool = Raise;
    test.brush.radius = 15;
    test.brush.begin(-20, -20);
    test.brush.apply(-20, -20, 1);
    test.brush.finish();
    equals(test.state.terrain.heightAt(-20, -20), 0, "model hücresi fırçayla değişmemeli");
    test.brush.tool = Scatter;
    test.brush.scatterType = "rock";
    test.brush.density = 0.2;
    test.brush.begin(-20, -20);
    test.brush.apply(-20, -20, 0.1);
    test.brush.finish();
    check(test.state.scatter.get(0).items.length > 0, "model hücresine dağıtma yapılmalı");
  }

  // Model hücrelere ağırlık merkezine göre bölünür, aynı model aynı baytları verir.
  static function testSurfaces() {
    var world = new WorldData("world", 2, 1, 20, 2, []);
    var group = {
      texture: "world/textures/a.jpg",
      positions: [-15., 0, 1, -5, 0, 1, -5, 5, 1, 5, 0, 2, 15, 0, 2, 15, 5, 2, -3, 0, 3, 1, 0, 3, -3, 5, 3],
      normals: [for (i in 0...9) for (axis in [0., 0, 1]) axis],
      uvs: [for (i in 0...18) i * 0.1],
      indexes: [0, 1, 2, 3, 4, 5, 6, 7, 8],
    };
    var parts = TerrainModelBaker.surfaces(world, [group]);
    equals(parts.get(0).triangleCount(), 2, "sol hücreye iki üçgen, biri sınırı aşsa da");
    equals(parts.get(1).triangleCount(), 1, "sağ hücreye bir üçgen");
    equals(parts.get(1).groups[0].positions.length, 9, "yalnızca kullanılan köşeler");
    equals(parts.get(1).groups[0].indexes.join(","), "0,1,2", "yeniden numaralanır");
    equals(parts.get(0).groups[0].texture, "world/textures/a.jpg", "doku taşınır");
    var bytes = parts.get(0).write();
    var again = TerrainModelBaker.surfaces(world, [group]).get(0).write();
    equals(bytes.compare(again), 0, "aynı model aynı baytlar");
    var read = TerrainSurface.read(bytes);
    equals(read.triangleCount(), 2, "parça okunmalı");
    equals(read.write().compare(bytes), 0, "parça dosyası kararlı");
    check(Math.abs(read.groups[0].uvs[1] - 0.1) < 1e-6, "uv korunmalı");
  }

  static function testNavRules() {
    // Çokgen alan kapalı, dışı açık
    var world = new WorldData("world", 1, 1, 20, 2, []);
    world.navResolution = 20;
    var terrain = new WorldTerrain(world);
    terrain.set(0, TerrainCell.flat(2));
    var area = NavShapes.polygon([-5., -5, 5, -5, 0, 5]);
    var baked = NavBaker.bake(0, world, terrain, [area]);
    check(baked.isBlocked(10, 8), "üçgen alanın içi kapalı");
    check(!baked.isBlocked(2, 18), "alanın dışı açık");
    check(baked.isBlocked(10, 4), "kenarın hemen dışı da kapalı, karakter sınırı sıyırmasın");

    // Eğim sınırı ayarlanabilir
    var hill = TerrainCell.flat(2);
    hill.setHeight(2, 0, 12);
    hill.setHeight(2, 1, 12);
    hill.setHeight(2, 2, 12);
    terrain.set(0, hill);
    world.maxSlope = 42;
    check(NavBaker.bake(0, world, terrain, []).isBlocked(15, 10), "dik tepe kapalı");
    world.maxSlope = 90;
    check(!NavBaker.bake(0, world, terrain, []).isBlocked(15, 10), "eğim sınırı kalkınca tepeye çıkılır");
  }

  // Eklem adları: Rigify (DEF- önce, ORG- sonra), mixamorig öneki, düz Mixamo; elle eşleme önce gelir.
  static function testJointNames() {
    var rigify = scene.JointNames.resolve(["DEF-hips", "DEF-spine.001", "DEF-hand.R", "ORG-hand.R", "DEF-hand.L", "ORG-foot.R", "DEF-thigh.L"]);
    equals(rigify.get("Hips"), "DEF-hips", "Rigify kalça");
    equals(rigify.get("Spine"), "DEF-spine.001", "Rigify omurga");
    equals(rigify.get("RightHand"), "DEF-hand.R", "DEF, ORG'dan önce");
    equals(rigify.get("RightFoot"), "ORG-foot.R", "DEF yoksa ORG");
    equals(rigify.get("LeftUpLeg"), "DEF-thigh.L", "sol uyluk");
    check(!rigify.exists("Head"), "iskelette olmayan eklem eşlenmez");
    equals(scene.JointNames.resolve(["mixamorig:Hips"]).get("Hips"), "mixamorig:Hips", "mixamorig öneki");
    equals(scene.JointNames.resolve(["Hips", "mixamorig:Hips"]).get("Hips"), "Hips", "düz ad önce");
    var overrides = ["Hips" => "pelvis", "Head" => "yok_boyle"];
    var mapped = scene.JointNames.resolve(["pelvis", "Hips", "DEF-head"], overrides);
    equals(mapped.get("Hips"), "pelvis", "elle eşleme önce");
    equals(mapped.get("Head"), "DEF-head", "elle verilen ad iskelette yoksa bilinen adlar denenir");
    equals(scene.JointNames.actual(null, "Hips"), "Hips", "eşleme yoksa standart ad");
    equals(scene.JointNames.actual(rigify, "Head"), "Head", "eşlemede yoksa standart ad");
    var back = scene.JointNames.fromData(haxe.Json.parse(haxe.Json.stringify(scene.JointNames.toData(rigify))));
    equals([for (k => v in back) '$k=$v'].length, [for (k in rigify.keys()) k].length, "eşleme JSON'dan geri okunur");
    equals(back.get("RightFoot"), "ORG-foot.R", "geri okunan ad");
    equals(scene.JointNames.fromData(null), null, "eşlemesiz bilgi dosyası");
  }

  // Model başvurusu: katalog kimliği dosyaya çözülür, yol olduğu gibi kalır (eski içerik, modlar).
  static function testModelRef() {
    var saved = scene.ModelRef.catalog;
    scene.ModelRef.catalog = null;
    equals(scene.ModelRef.file("models/a/a.hmd"), "models/a/a.hmd", "katalog yokken yol");
    equals(scene.ModelRef.file("sovalye"), "", "katalog yokken kimlik çözülmez");
    scene.ModelRef.catalog = id -> id == "sovalye" ? "models/mock/iv_knight/iv_knight.hmd" : null;
    equals(scene.ModelRef.file("sovalye"), "models/mock/iv_knight/iv_knight.hmd", "kimlik dosyaya çözülür");
    equals(scene.ModelRef.file("yok_boyle"), "", "katalogda olmayan kimlik");
    equals(scene.ModelRef.file("models/lamborghini/lamborghini.fbx"), "models/lamborghini/lamborghini.fbx", "eski yol katalogdan geçmez");
    equals(scene.ModelRef.file(""), "", "boş başvuru");
    equals(scene.ModelRef.file(null), "", "başvuru yok");
    check(scene.ModelRef.isPath("araba.fbx") && !scene.ModelRef.isPath("kisa_kilic"), "uzantı yol sayılır, kimlik sayılmaz");
    scene.ModelRef.catalog = saved;
  }

  // İçe aktarma ayarları: klip, boy ve kutu kuralları; klasör ayarı birleştirme; eski dosyanın kararlı yazılması.
  static function testImportSettings() {
    function fails(run : () -> Void, label : String, ?pos : haxe.PosInfos) check(try { run(); false; } catch (e : Dynamic) true, label, pos);
    var own = ImportSettings.checkClip({name: "durma", source: "", take: "Idle_Loop"});
    equals(own.take, "Idle_Loop", "kendi dosyasından klip");
    fails(() -> ImportSettings.checkClip({name: "durma", source: ""}), "kaynaksız klibin take'i olmalı");
    fails(() -> ImportSettings.checkClip({name: "durma", source: "a.glb", take: "x"}), "klip kaynağı FBX olmalı");
    fails(() -> ImportSettings.checkClip({name: "Durma", source: "a.fbx"}), "klip adı küçük harf");
    fails(() -> ImportSettings.checkClip({name: "durma", source: "a.fbx", arms: "b.obj"}), "kollar FBX olmalı");
    equals(ImportSettings.checkClip({name: "durma", source: "a\\b.fbx", take: ""}).take, null, "boş take yok sayılır");
    equals(ImportSettings.checkClip({name: "durma", source: "a\\b.fbx"}).source, "a/b.fbx", "ters bölü düzelir");
    equals(ImportSettings.checkLength(0.75), 0.75, "boy");
    fails(() -> ImportSettings.checkLength(0), "sıfır boy");
    fails(() -> ImportSettings.checkLength(101), "çok büyük boy");
    fails(() -> ImportSettings.checkLength("bir"), "sayı olmayan boy");
    fails(() -> ImportSettings.checkBox({min: [1., 0., 0.], max: [0., 0., 0.]}), "kutuda min, max'tan büyük olamaz");

    // Geçici klasör: yalnızca bu testin yazdığı dosyalar silinir.
    var base = Sys.getEnv("TMPDIR");
    var root = (base == null ? "/tmp" : base) + "/aktarim_testi_" + Std.random(1000000000);
    var pack = '$root/assets/models/paket', folder = '$pack/${ImportSettings.FOLDER_FILE}';
    sys.FileSystem.createDirectory('$pack/sovalye');
    var source = '$pack/sovalye/sovalye.fbx';
    var shared = new ImportSettings();
    shared.clips = [{name: "durma", source: "", take: "Idle_Loop"}, {name: "yurume", source: "", take: "Walk_Loop"}];
    shared.sockets = [{name: "sag_el", joint: "DEF-hand.R", offset: [0., 0., 0.], rotation: [0., 0., 0.]}];
    shared.joints.set("Hips", "pelvis");
    shared.length = 0.9;
    shared.grip = true;
    shared.trim = [{min: [0., 0., 0.], max: [1., 1., 1.]}];
    shared.write(source, folder);
    equals(ImportSettings.folderFiles(source).join(","), folder, "klasör ayarı bulunur");
    var inherited = ImportSettings.effective(source);
    equals(inherited.clips.length, 2, "klasörün klipleri");
    equals(inherited.joints.get("Hips"), "pelvis", "klasörün eklem eşlemesi");
    equals(inherited.trim.length, 0, "kırpma klasörden gelmez");
    equals(inherited.inherited.length, 1, "etkin ayar klasör dosyasını bilir");
    var mine = new ImportSettings();
    mine.clips = [{name: "yurume", source: "", take: "Walk_Formal_Loop"}];
    mine.length = 0.75;
    mine.blender = true;
    mine.trim = [{min: [0., 0., 0.], max: [0.1, 0.1, 0.1], note: "plaka"}];
    mine.write(source);
    var merged = ImportSettings.effective(source);
    equals(merged.clips.length, 2, "aynı adlı klip ezilir, sayı artmaz");
    equals(Lambda.find(merged.clips, c -> c.name == "yurume").take, "Walk_Formal_Loop", "modelin klibi klasörünkünü ezer");
    equals(merged.length, 0.75, "modelin boyu");
    equals(merged.grip, true, "klasörün tutamak ayarı kalır");
    equals(merged.blender, true, "modelin blender ayarı");
    equals(merged.sockets.length, 1, "klasörün takma noktası");
    equals(merged.trim.length, 1, "kırpma modelin dosyasından");
    equals(ImportSettings.read(source).joints.exists("Hips"), false, "modelin kendi dosyası klasörünkünü içermez");

    // Yeni alanları kullanmayan dosya yeniden yazılınca aynı kalır.
    var plain = '$pack/sovalye/eski.fbx';
    var old = new ImportSettings();
    old.clips = [{name: "durma", source: "x.fbx"}];
    old.write(plain);
    var text = sys.io.File.getContent(ImportSettings.path(plain));
    check(text.indexOf('"joints"') < 0 && text.indexOf('"length"') < 0 && text.indexOf('"grip"') < 0 && text.indexOf('"blender"') < 0, "eski dosyaya yeni alan yazılmaz");
    ImportSettings.read(plain).write(plain);
    equals(sys.io.File.getContent(ImportSettings.path(plain)), text, "eski dosya kararlı");

    for (file in [folder, ImportSettings.path(source), ImportSettings.path(plain)]) sys.FileSystem.deleteFile(file);
    for (dir in ['$pack/sovalye', pack, '$root/assets/models', '$root/assets', root]) sys.FileSystem.deleteDirectory(dir);
  }

  // Dosya yolu sütunu ve tablo değişince oyun verisinin yeniden okunması. Takma noktaları (ImportSettings)
  // Heaps ister, editör düzeneğinde import_model ile sınanır.
  static function testSockets() {
    check(DataTable.TYPES.indexOf(DataTable.ASSET) >= 0, "dosya yolu sütun türü");
    var items = new DataTable("esyalar", "Eşyalar");
    items.columns = [{name: "model", title: "Model", type: DataTable.ASSET}];
    equals(items.addRow("tufek").get("model"), "", "dosya yolu varsayılanı boş");
    items.find("tufek").set("model", "models/tufek/tufek.hmd");
    var text = items.write();
    equals(DataTable.read("esyalar", text).find("tufek").get("model"), "models/tufek/tufek.hmd", "dosya yolu okunmalı");

    var files = ["data/esyalar.table.json" => text];
    var data = new GameData(path -> files.get(path));
    equals(data.row("esyalar", "tufek").get("model"), "models/tufek/tufek.hmd", "oyun satırı");
    items.find("tufek").set("model", "");
    files.set("data/esyalar.table.json", items.write());
    equals(data.row("esyalar", "tufek").get("model"), "models/tufek/tufek.hmd", "önbellek forget'e kadar eskiyi verir");
    data.forget("esyalar");
    equals(data.row("esyalar", "tufek").get("model"), "", "forget sonrası yeni dosya okunmalı");
  }

  static function testDataTables() {
    var table = new DataTable("esyalar", "Eşyalar");
    table.columns = [
      {name: "ad", title: "Ad", type: DataTable.TEXT},
      {name: "deger", title: "Değer", type: DataTable.INTEGER},
      {name: "tur", title: "Tür", type: DataTable.CHOICE, options: ["silah", "yiyecek"]},
      {name: "sahip", title: "Sahip", type: DataTable.REFERENCE, table: "fraksiyonlar"},
    ];
    var sword = table.addRow("kilic");
    equals(sword.get("deger"), 0, "tam sayı varsayılanı");
    equals(sword.get("tur"), "silah", "seçim varsayılanı ilk seçenek");
    sword.set("ad", "Kılıç \"keskin\"");
    equals(table.freeId("kilic"), "kilic_2", "boş kimlik");
    table.addRow("ekmek").set("ad", "");
    var text = table.write();
    var read = DataTable.read("esyalar", text);
    equals(read.rows.length, 2, "satırlar okunmalı");
    equals(read.find("kilic").get("ad"), "Kılıç \"keskin\"", "tırnaklı metin korunmalı");
    equals(read.write(), text, "tablo dosyası kararlı");
    equals(read.label("kilic"), "kilic (Kılıç \"keskin\")", "liste etiketi addan gelir");
    equals(read.label("ekmek"), "ekmek", "adsız satır kimlikle görünür");
    check(text.split("\n").length >= 8, "her satır ayrı satıra yazılmalı");
    read.columns.push({name: "agirlik", title: "Ağırlık", type: DataTable.NUMBER});
    check(read.write().indexOf('"agirlik": 0') >= 0, "yeni sütun varsayılanla yazılmalı");

    var files = ["data/esyalar.table.json" => text];
    var data = new GameData(path -> files.get(path));
    check(data.exists("esyalar", "kilic"), "oyun satırı bulmalı");
    check(!data.exists("esyalar", "yok"), "olmayan satır");
    check(!data.exists("yok", "kilic"), "olmayan tablo");

    // Derleme: tablodan silinen satırı kullanan sahne durur
    var schema = new SceneSchema();
    schema.add(["spawn"], ["faction" => "String"], null, ["faction" => "fraksiyonlar"]);
    var scene = new SceneData(SceneFormat.VERSION);
    var item = new EntityData("a", "Kamp");
    var spawn = new ComponentData("spawn");
    spawn.fields.set("faction", "haydut");
    item.components.push(spawn);
    scene.entities.push(item);
    equals(schema.check(SceneFormat.write(scene), null, (t, id) -> id == "haydut").length, 0, "var olan satır");
    // Satır içeriktir: silinmesi ekibin derlemesini durdurmaz, uyarı olur.
    var problems = schema.check(SceneFormat.write(scene), null, (t, id) -> false);
    equals(problems.length, 0, "silinen satır derlemeyi durdurmamalı");
    equals(schema.warnings.length, 1, "silinen satır uyarı olmalı");
    check(schema.warnings[0].indexOf("fraksiyonlar") >= 0, 'uyarı tabloyu söylemeli: ${schema.warnings[0]}');
    schema.check(SceneFormat.write(scene), null, (t, id) -> true);
    equals(schema.warnings.length, 0, "uyarılar her kontrolde sıfırlanmalı");
  }

  static function questDialog() {
    var dialog = Dialog.create("muhtar", "Muhtar");
    var line = dialog.node(2);
    line.speaker = "Muhtar";
    line.text = "Haydutlar kılıcımı çaldı.";
    line.next = 4;
    dialog.nodes.push({id: 4, type: Dialog.CONDITION, x: 0, y: 0, kind: Dialog.ITEM, name: "kilic", value: 1, yes: 5, no: 6});
    dialog.nodes.push({id: 5, type: Dialog.LINE, x: 0, y: 0, speaker: "Muhtar", text: "Kılıcımı buldun!", next: 3});
    dialog.nodes.push({id: 6, type: Dialog.CHOICES, x: 0, y: 0, choices: [{text: "Yardım ederim", next: 7}, {text: "Hayır", next: 3}]});
    dialog.nodes.push({id: 7, type: Dialog.EVENT, x: 0, y: 0, event: "gorev_kabul", next: 3});
    return dialog;
  }

  // Editör açıkken dışarıda değişen dosya: birimler ayrı ayrı birleşir, aynı birim çakışır.
  static function testThreeWay() {
    var merge = scene.data.ThreeWay;
    function sceneOf(names : Array<String>) {
      var data = new SceneData(SceneFormat.VERSION);
      for (name in names) {
        var parts = name.split("=");
        data.entities.push(new scene.data.SceneData.EntityData(parts[0], parts[1]));
      }
      return SceneFormat.write(data);
    }
    function names(text : Null<String>) {
      return text == null ? "çakışma" : [for (entity in SceneFormat.read(text).entities) '${entity.id}=${entity.name}'].join(",");
    }
    var base = sceneOf(["a=Ev", "b=Kuyu"]);
    var result = merge.scene(base, sceneOf(["a=Büyük ev", "b=Kuyu"]), sceneOf(["a=Ev", "b=Eski kuyu", "c=Devriye"]));
    equals(names(result.text), "a=Büyük ev,b=Eski kuyu,c=Devriye", "iki tarafın farklı nesneleri birleşmeli");
    equals(result.conflicts.length, 0, "farklı nesnelerde çakışma yok");
    result = merge.scene(base, sceneOf(["a=Benim ev", "b=Kuyu"]), sceneOf(["a=Onun ev", "b=Kuyu"]));
    check(result.text == null && result.conflicts[0] == "Benim ev", 'aynı nesne çakışmalı: ${result.conflicts}');
    equals(names(merge.scene(base, sceneOf(["a=Benim ev", "b=Kuyu"]), sceneOf(["a=Onun ev", "b=Kuyu"]), merge.MINE).text), "a=Benim ev,b=Kuyu", "çakışmada benimki");
    equals(names(merge.scene(base, sceneOf(["a=Benim ev", "b=Kuyu"]), sceneOf(["a=Onun ev", "b=Kuyu"]), merge.THEIRS).text), "a=Onun ev,b=Kuyu", "çakışmada diskteki");
    result = merge.scene(base, sceneOf(["b=Kuyu"]), sceneOf(["a=Onun ev", "b=Kuyu"]));
    check(result.text == null, "biri silip öbürü değiştirince çakışmalı");
    equals(names(merge.scene(base, sceneOf(["b=Kuyu"]), base).text), "b=Kuyu", "yalnızca benim silmem kalmalı");
    equals(names(merge.scene(base, base, sceneOf(["b=Kuyu"])).text), "b=Kuyu", "yalnızca diskteki silme kalmalı");
    equals(names(merge.scene(null, sceneOf(["a=Ev"]), sceneOf(["b=Kuyu"])).text), "b=Kuyu,a=Ev", "tabansız yeni dosyada iki taraf da kalır");

    var table = '{"version":1,"title":"Eşyalar","columns":[{"name":"ad","title":"Ad","type":"metin"}],"rows":[{"id":"kilic","ad":"Kılıç"}]}';
    var mineTable = '{"version":1,"title":"Eşyalar","columns":[{"name":"ad","title":"Ad","type":"metin"}],"rows":[{"id":"kilic","ad":"Uzun kılıç"}]}';
    var theirTable = '{"version":1,"title":"Eşyalar","columns":[{"name":"ad","title":"Ad","type":"metin"},{"name":"deger","title":"Değer","type":"tam"}],"rows":[{"id":"kilic","ad":"Kılıç"},{"id":"su","ad":"Su","deger":3}]}';
    var merged = DataTable.read("esyalar", merge.table("esyalar", table, mineTable, theirTable).text);
    equals(merged.columns.length, 2, "diskte eklenen sütun kalmalı");
    equals(merged.find("kilic").get("ad"), "Uzun kılıç", "benim satır değişikliğim kalmalı");
    check(merged.find("su") != null, "diskte eklenen satır kalmalı");

    var dialog = scene.story.Dialog.create("muhtar", "Muhtar");
    var mineDialog = dialog.clone();
    mineDialog.node(2).text = "Merhaba";
    var theirDialog = dialog.clone();
    theirDialog.nodes.push({id: 4, type: scene.story.Dialog.EVENT, x: 0, y: 0, event: "selam", next: 3});
    var joined = scene.story.Dialog.read("muhtar", merge.dialog("muhtar", dialog.write(), mineDialog.write(), theirDialog.write()).text);
    check(joined.node(2).text == "Merhaba" && joined.node(4) != null, "diyalogda iki tarafın düğümleri birleşmeli");
    var otherText = dialog.clone();
    otherText.node(2).text = "Selam";
    check(merge.dialog("muhtar", dialog.write(), mineDialog.write(), otherText.write()).text == null, "aynı düğüm çakışmalı");

    equals(merge.whole("x", "x", "y").text, "y", "değiştirmediğim dosyada diskteki");
    check(merge.whole("x", "z", "y").text == null, "iki taraf da değiştirdiyse bütün dosya çakışır");
    equals(merge.whole("x", null, "x").text, null, "yalnızca ben sildiysem silinir");
  }

  // Yerleşim veriden hesaplanır: konumlar ekran netliğine ve önceki konumlara bağlı değildir.
  static function testDialogLayout() {
    var dialog = questDialog();
    var first = scene.story.DialogLayout.arrange(dialog);
    for (node in dialog.nodes) {
      node.x = node.id * 37;
      node.y = -node.id * 11;
    }
    var again = scene.story.DialogLayout.arrange(dialog);
    var same = true;
    for (id => at in first) if (again.get(id).x != at.x || again.get(id).y != at.y) same = false;
    check(same, "yerleşim eski konumlardan etkilenmemeli");
    var start = first.get(dialog.start().id);
    check(start.x == 0 && start.y == 0, "başlangıç sol üstte");
    for (id => at in first) {
      var column = at.x / scene.story.DialogLayout.COLUMN_STEP;
      check(column == Math.ffloor(column), 'sütun adımı sabit olmalı: ${at.x}');
      for (other => there in first) {
        if (other == id || there.x != at.x || there.y <= at.y) continue;
        check(there.y >= at.y + scene.story.DialogLayout.height(dialog.node(id)), 'aynı sütunda üst üste binmemeli: $id $other');
      }
    }
    equals(scene.story.DialogLayout.wrappedLines("abc def", 3), 2, "boşluktan kaydırma");
    equals(scene.story.DialogLayout.wrappedLines("abcdefg", 3), 3, "uzun kelime bölünür");
    equals(scene.story.DialogLayout.wrappedLines("a\nb", 10), 2, "Enter yeni satır");
    equals(scene.story.DialogLayout.wrappedLines("kısa", 26), 1, "sığan metin tek satır");
  }

  static function testStory() {
    var dialog = questDialog();
    var text = dialog.write();
    var read = Dialog.read("muhtar", text);
    equals(read.write(), text, "diyalog dosyası kararlı");
    equals(read.nodes.length, 7, "düğümler okunmalı");
    var shuffled = read.clone();
    shuffled.nodes.reverse();
    equals(shuffled.write(), text, "düğüm sırası dosyayı değiştirmemeli");

    var files = ["data/dialogs/muhtar.dialog.json" => text];
    var story = new Story(path -> files.get(path));
    var scene = newScene(Game);
    var types = registry();
    types.register(GiveCount);
    types.register(NeedFlag);
    var events = new SceneInstance(types, Game, new Object());
    var reward = events.createEntity("Ödül", "o");
    reward.addComponent(new NeedFlag());
    var give = new GiveCount();
    reward.addComponent(give);
    story.listen("gorev_kabul", reward);

    // Kılıç yok: seçenekler gelir
    story.startDialog("muhtar");
    var runner = story.dialog;
    check(runner != null, "diyalog açılmalı");
    equals(runner.speaker, "Muhtar", "konuşan");
    equals(runner.text, "Haydutlar kılıcımı çaldı.", "satır");
    runner.next();
    equals(runner.choices.join("|"), "Yardım ederim|Hayır", "eşya yoksa seçenek dalı");
    // Koşul sağlanmadığı için olay eylem çalıştırmaz
    runner.choose(0);
    check(runner.finished, "olaydan sonra bitmeli");
    equals(story.state.count("ekmek"), 0, "koşul sağlanmazsa eylem çalışmamalı");
    story.closeDialogIfFinished();
    check(story.dialog == null, "biten diyalog kapanmalı");

    story.state.setFlag("izin", 1);
    story.emit("gorev_kabul");
    equals(story.state.count("ekmek"), 2, "olay eylemi çalıştırmalı");

    // Kılıç varsa diğer dal
    story.state.give("kilic", 1);
    story.startDialog("muhtar");
    story.dialog.next();
    equals(story.dialog.text, "Kılıcımı buldun!", "eşya varsa evet dalı");
    story.dialog.next();
    check(story.dialog.finished, "bitiş");

    // İlişki koşulu (docs/NPC_DAVRANIS_PLANI.md, 1. adım): değeri oyun verir (Story.standingOf: başlangıç ilişkisi ve
    // ölçek oyunun tablosunda); bağlı değilse kayıttaki değer.
    var greet = new Dialog("selam", "Selam");
    greet.nodes.push({id: 1, type: Dialog.START, x: 0, y: 0, next: 2});
    greet.nodes.push({id: 2, type: Dialog.CONDITION, x: 0, y: 0, kind: Dialog.STANDING, name: "kasaba", value: 25, yes: 3, no: 4});
    greet.nodes.push({id: 3, type: Dialog.LINE, x: 0, y: 0, speaker: "Bekçi", text: "Hoş geldin.", next: 5});
    greet.nodes.push({id: 4, type: Dialog.LINE, x: 0, y: 0, speaker: "Bekçi", text: "Defol.", next: 5});
    greet.nodes.push({id: 5, type: Dialog.END, x: 0, y: 0});
    var greetFiles = ["data/dialogs/selam.dialog.json" => greet.write()];
    var talk = new Story(path -> greetFiles.get(path));
    talk.startDialog("selam");
    equals(talk.dialog.text, "Defol.", "ilişki koşulu: kayıtta ilişki yok (0), hayır dalı");
    talk.state.changeStanding("kasaba", 30);
    talk.startDialog("selam");
    equals(talk.dialog.text, "Hoş geldin.", "ilişki koşulu: kayıttaki ilişki 30, evet dalı");
    talk.standingOf = faction -> faction == "kasaba" ? -10 : 0;
    talk.startDialog("selam");
    equals(talk.dialog.text, "Defol.", "ilişki koşulu: oyunun verdiği ilişki okunur (kayıttakinin yerine)");
    // "iliski" değişikliğinin değeri ve GameState.relation da oyunun değeri (olay kaydı, günlük, F3 ve ajan aynısını görür).
    var reported = [];
    talk.state.watch((kind, name, value) -> if (kind == "iliski") reported.push('$name $value'));
    var start = 50;
    talk.standingOf = faction -> faction == "kasaba" ? start + talk.state.standingWith(faction) : 0;
    talk.state.changeStanding("kasaba", 5);
    equals(reported.join(","), "kasaba 85", "ilişki değişikliği oyunun değerini bildirir (başlangıç 50 + kayıtta 35)");
    equals(talk.state.relation("kasaba"), 85, "GameState.relation oyunun değeri");
    equals(talk.state.standingWith("kasaba"), 35, "kayıt değişimi tutar");
    equals(Dialog.read("selam", greet.write()).write(), greet.write(), "ilişki koşullu diyalog dosyası kararlı");

    story.startDialog("yok");
    check(story.dialog == null || story.dialog.finished, "olmayan diyalog açılmamalı");
    equals(story.messages[story.messages.length - 1], "Diyalog bulunamadı: yok", "olmayan diyalog bildirilmeli");

    // Düğüm silinince bağlantılar da kalkar
    var removed = questDialog();
    removed.remove(7);
    equals(removed.node(6).choices[0].next, 0, "silinen düğüme bağlantı kalkmalı");
    equals(removed.freeId(), 7, "boş kimlik");

    // Durum
    var state = new GameState();
    state.give("ekmek", 3);
    state.give("ekmek", -3);
    check(!state.items.exists("ekmek"), "biten eşya listeden çıkmalı");
    state.changeStanding("kasaba", 10);
    state.changeStanding("kasaba", -4);
    equals(state.standingWith("kasaba"), 6, "ilişki birikmeli");

    // Eşya deposu: verilen eşya depoya gider, toplamlar sync ile gelir, dinleyiciler değişeni duyar.
    var depot = new Map<String, Int>();
    var heard = [];
    var stored = new GameState();
    stored.watch((kind, name, value) -> heard.push('$kind/$name=$value'));
    stored.store = new FakeStore(depot, stored);
    stored.give("ekmek", 4);
    equals(stored.count("ekmek"), 4, "depodan sayılır");
    equals(depot.get("ekmek"), 4, "depoya gitti");
    stored.give("ekmek", -4);
    check(!stored.items.exists("ekmek") && heard.join(" ") == "esya/ekmek=4 esya/ekmek=0", 'dinleyiciler: ${heard.join(" ")}');
    var before = stored.revision;
    stored.sync(new Map());
    equals(stored.revision, before, "değişmeyen toplam yeniden çizdirmez");
  }

  static function testValidator() {
    var types = new ComponentRegistry();
    types.register(Pointer);
    var scene = new SceneInstance(types, Editor, new Object());
    var entity = scene.createEntity("Ok", "aaaaaaaaaaaaaaaa");
    @:privateAccess scene.isReady = true;
    var pointer = entity.addComponent(new Pointer());
    var fields = pointer.describeFields();
    equals(fields.length, 6, "tüm alanlar");
    switch (fields[2].hint) {
      case HChoice(options): equals(options.join(","), "kolay,zor", "seçenekler");
      default: check(false, "seçim alanı");
    }
    equals(fields[3].hint, FieldHint.HColor, "renk alanı");
    equals(fields[4].kind, FieldKind.KStringList, "metin listesi");
    equals(fields[5].kind, FieldKind.KFloatList, "sayı listesi");
    check(pointer.writeField("tags", ["a", "b"]), "liste yazılmalı");
    equals(pointer.tags.length, 2, "liste okunmalı");
    equals(pointer.tags[1], "b", "liste değeri");
    pointer.writeField("speeds", [1.5, 2]);
    equals(pointer.speeds[0], 1.5, "sayı listesi değeri");
    equals(fields[0].hint, FieldHint.HAsset, "asset alanı");
    equals(fields[1].hint, FieldHint.HEntity, "nesne alanı");

    var validator = new Validator(path -> path == "var.fbx");
    equals(validator.run(scene).length, 0, "boş alan uyarı vermemeli");
    pointer.model = "var.fbx";
    pointer.target = "aaaaaaaaaaaaaaaa";
    equals(validator.run(scene).length, 0, "geçerli alan uyarı vermemeli");
    pointer.model = "yok.fbx";
    pointer.target = "bbbbbbbbbbbbbbbb";
    var issues = validator.run(scene);
    equals(issues.length, 2, "iki sorun");
    equals(issues[0].entity, entity, "sorun nesneyi göstermeli");
    equals(issues[0].message, 'Ok: eksik asset "yok.fbx" (Model)', "asset uyarısı");
    validator.rules.push(_ -> [{entity: entity, message: "oyun kuralı"}]);
    equals(validator.run(scene).length, 3, "oyun kuralı eklenebilmeli");
  }

  static function testPlayOptions() {
    equals(PlayOptions.parse([]), null, "seçenek yok");
    equals(PlayOptions.parse(["--play"]), null, "eksik sahne");
    var options = new PlayOptions("scenes/a.scene.json", [1, 2.5, -3, 4, 5, 6]);
    var parsed = PlayOptions.parse(options.toArgs());
    equals(parsed.scene, "scenes/a.scene.json", "sahne");
    equals(parsed.camera.length, 6, "kamera");
    near(parsed.camera[1], 2.5, "kamera değeri");
    near(parsed.camera[2], -3, "negatif değer");
    equals(PlayOptions.parse(new PlayOptions("x").toArgs()).camera, null, "kamera isteğe bağlı");
  }

  static function testGuid() {
    var seen = new Map<String, Bool>();
    for (i in 0...2000) seen.set(Guid.make(), true);
    equals(Lambda.count(seen), 2000, "kimlikler benzersiz olmalı");
    equals(Guid.make().length, 16, "kimlik uzunluğu");
  }

  static function testDestroy() {
    var scene = sample();
    var parent = scene.find("aaaaaaaaaaaaaaaa");
    var crate = scene.find("bbbbbbbbbbbbbbbb").getComponent(HeavyCrate);
    scene.destroyEntity(parent);
    equals(scene.entities.length, 0, "alt nesneler de silinmeli");
    equals(crate.destroyed, 1, "alt nesnenin bileşeni temizlenmeli");
  }

  static function main() {
    testNumbers();
    testRoundTrip();
    testEmptyScene();
    testChildBeforeParent();
    testMissingParent();
    testUnknownDataSurvives();
    testRenames();
    testRegistryErrors();
    testSchema();
    testVersions();
    testMacro();
    testLifecycle();
    testCommands();
    testProjectScenes();
    testGuid();
    testDestroy();
    testDetach();
    testEntityCommands();
    testVisibility();
    testBrokenComponent();
    testSelection();
    testLockGroups();
    testPrefabs();
    testPrefabUndo();
    testChoiceValues();
    testWorldGrid();
    testTerrainCell();
    testWorldTerrain();
    testStreaming();
    testEntityLookup();
    testForgetCommands();
    testJointNames();
    testImportSettings();
    testModelRef();
    testBrushes();
    testBrushLockedEdges();
    testScatterBrush();
    testNav();
    testTerrainModels();
    testNavRules();
    testSurfaces();
    testDataTables();
    testWorldDelta();
    testSaveFiles();
    testRandom();
    testRuntimeEntities();
    testSaveVersions();
    testSaveWriter();
    testTuner();
    testSockets();
    testStory();
    testDialogLayout();
    testThreeWay();
    testEnvironment();
    testPrefabFailures();
    testPrefabSchema();
    testGizmoMath();
    testValidator();
    testPlayOptions();
    Sys.println('$checks kontrol, $failures hata');
    if (failures > 0) Sys.exit(1);
  }
}

class FakeStore implements scene.story.GameState.ItemStore {
  var depot : Map<String, Int>;
  var state : GameState;

  public function new(depot : Map<String, Int>, state : GameState) {
    this.depot = depot;
    this.state = state;
  }

  public function give(item : String, amount : Int) {
    var total = (depot.exists(item) ? depot.get(item) : 0) + amount;
    if (total <= 0) depot.remove(item) else depot.set(item, total);
    state.sync(depot.copy());
  }
}
