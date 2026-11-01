import h3d.scene.Object;
import scene.Component;
import scene.ComponentRegistry;
import scene.FieldInfo.FieldKind;
import scene.Guid;
import scene.SceneInstance;
import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.data.SceneSchema;
import scene.editor.CommandStack;
import scene.editor.commands.SetFieldCommand;
import scene.editor.commands.SetNameCommand;
import scene.editor.commands.SetTransformCommand;

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

class NoIdentity extends Component {}

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
    Sys.println('$checks kontrol, $failures hata');
    if (failures > 0) Sys.exit(1);
  }
}
