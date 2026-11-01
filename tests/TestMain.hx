import h3d.scene.Object;
import scene.Component;
import scene.ComponentRegistry;
import scene.FieldInfo.FieldHint;
import scene.FieldInfo.FieldKind;
import scene.Guid;
import scene.PlayOptions;
import scene.SceneInstance;
import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.data.SceneSchema;
import scene.editor.CommandStack;
import scene.editor.GizmoMath;
import scene.editor.LockGroups;
import scene.editor.Selection;
import scene.editor.Validator;
import scene.editor.Vec3;
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

  static function testValidator() {
    var types = new ComponentRegistry();
    types.register(Pointer);
    var scene = new SceneInstance(types, Editor, new Object());
    var entity = scene.createEntity("Ok", "aaaaaaaaaaaaaaaa");
    @:privateAccess scene.isReady = true;
    var pointer = entity.addComponent(new Pointer());
    var fields = pointer.describeFields();
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
    testGizmoMath();
    testValidator();
    testPlayOptions();
    Sys.println('$checks kontrol, $failures hata');
    if (failures > 0) Sys.exit(1);
  }
}
