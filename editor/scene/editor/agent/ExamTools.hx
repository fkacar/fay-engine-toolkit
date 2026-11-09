package scene.editor.agent;

import scene.editor.TranslationStatus;

import scene.Entity;
import scene.PlayFiles;
import scene.data.SceneFormat;
import scene.world.WorldData;
import scene.editor.agent.AgentServer.AgentReply;
import scene.nav.NavWorld;
import sys.FileSystem;
import sys.io.File;

// Ajan sınavı: tasarımcı testlerinden ve fazların çıkış sorularından gelen görevler. Ajan görevi
// yapar, check_exam_task kontrolleri puanlar ve ajanın değişikliklerini geri alır; sonuç
// sonuclar.jsonl'a eklenir, sürümler arası karşılaştırılır. Kontroller ajana gösterilmez.
class ExamTools {
  public static inline var DIRECTORY = "tests/ajan-sinavi";
  public static inline var SUFFIX = ".sinav.json";
  // Yol ağı dosyaları kayıtta yeniden üretilir (türetilmiş): sınavdan önceki halleri saklanır, geri alınca yazılır.
  static inline var NAV_SUFFIX = ".nav.json";
  public static inline var RESULTS = "tests/ajan-sinavi/sonuclar.jsonl";
  public static inline var NEW = "$yeni";
  // Görevin sınav dışında bıraktığı test dosyaları silinmez, buraya taşınır.
  public static inline var LEFTOVERS = ".editor/sinav-artiklari";
  static inline var REACH = 2.;
  // Oyunun kendi kontrolleri (örneğin bir kabın içinde ne olduğu): tür adı → kontrol. Yeni nesneler verilir.
  public static var checks = new Map<String, (spec : Dynamic, created : Array<scene.Entity>) -> {ok : Bool, detail : String}>();

  var editor : Editor;
  var server : AgentServer;
  // origin: hazırlıktan önce (geri dönülecek hal), base: hazırlıktan sonra (ajanın başladığı hal).
  var current : Null<{id : String, task : Dynamic, origin : Baseline, base : Baseline}>;
  var results : Array<Dynamic> = [];

  public function new(editor : Editor, server : AgentServer) {
    this.editor = editor;
    this.server = server;
    function tool(name : String, description : String, properties : Dynamic, run : Dynamic->Dynamic, ?required : Array<String>) {
      var schema : Dynamic = {type: "object", properties: properties};
      if (required != null) schema.required = required;
      server.add({name: name, description: description, schema: schema, readOnly: name == "list_exam", run: args -> ({value: run(args)} : AgentReply)});
    }
    tool("list_exam", "Ajan sınavının görevleri: kimlik, başlık ve tasarımcının isteği.", {}, _ -> list());
    tool("start_exam_task", "Bir sınav görevini başlatır ve isteği verir. Görevi editör araçlarıyla yap, kaydetme, sonra check_exam_task.", {id: {type: "string"}}, args -> start(args.id), ["id"]);
    tool("check_exam_task", "Açık görevi puanlar, sonra görev sırasındaki değişiklikleri geri alır, kamerayı ve seçimi eski haline getirir.", {}, _ -> check());
    tool("finish_exam", "Sınavı bitirir, sonucu sonuclar.jsonl'a ekler ve önceki sonuçla karşılaştırır. model: kendi model adın. manual: elle puanlanan görevler, örn. {\"M1\": 2}.", {
      model: {type: "string"}, manual: {type: "object"}, note: {type: "string"},
    }, finish, ["model"]);
    server.addPrompt({name: "sinav", description: "Ajan sınavını çalıştır ve puanla",
      arguments: [{name: "elle", description: "Elle puanlanan görevler, örn. M1=2 M2=1 M3=2", required: false}],
      text: args -> (args.elle == null || args.elle == "" ? "" : 'Elle puanlar: ${args.elle}. Bunları finish_exam\'in manual alanına yaz. ') + "Ajan sınavı. list_exam ile görevleri al. Her görev için sırayla start_exam_task ile başlat; görevi tasarımcı istemiş gibi editör araçlarıyla yap, soru sorma, görev istemedikçe kaydetme; bitince check_exam_task çağır. Araç puanlar ve değişikliklerini geri alır. Hepsi bitince finish_exam'e model adını ver. Sonucu görev başına puanla bir tablo olarak göster, önceki sonuçla farkı ve kalan kontrolleri söyle."});
  }

  function list() : Dynamic {
    return [for (id in ids()) {
      var task = read(id);
      {id: id, title: task.title, prompt: task.prompt};
    }];
  }

  function start(id : String) : Dynamic {
    if (current != null) throw 'Açık görev var: ${current.id}. Önce check_exam_task.';
    var task = read(id);
    var origin = baseline();
    if (task.allowSave == true && !origin.clean)
      throw 'Bu görev kaydetmeyi gerektirir. Önce kaydedilmemiş işini kaydet: ${editor.document.unsavedFiles().join(", ")}';
    var steps : Array<Dynamic> = task.setup == null ? [] : task.setup;
    try {
      copyFiles(task, origin);
      for (step in steps) server.callTool(step.tool, prepare(step.arguments));
    } catch (e : Dynamic) {
      restore(origin);
      throw 'Sınav hazırlığı çalışmadı: $e';
    }
    current = {id: id, task: task, origin: origin, base: baseline()};
    return {id: id, title: task.title, prompt: task.prompt};
  }

  function check() : Dynamic {
    if (current == null) throw "Açık görev yok. Önce start_exam_task.";
    var task = current.task, base = current.base, origin = current.origin;
    editor.document.validate();
    var checks : Array<Dynamic> = task.checks;
    var outcome = [for (spec in checks) {
      var result = try evaluate(spec, base, origin) catch (e : Dynamic) {ok: false, detail: 'denetlenemedi: $e'};
      {check: spec.label != null ? spec.label : spec.type, ok: result.ok, detail: result.detail};
    }];
    var steps = editor.commands.undoCount - base.undoCount;
    var seconds = Math.round(haxe.Timer.stamp() - base.time);
    var cleanup = restore(origin);
    var passed = outcome.filter(item -> item.ok).length;
    var result = {id: current.id, passed: passed, total: outcome.length, steps: steps, seconds: seconds, checks: outcome, restored: cleanup};
    results = results.filter(other -> other.id != current.id);
    results.push(result);
    current = null;
    return result;
  }

  function finish(args : Dynamic) : Dynamic {
    if (current != null) throw 'Açık görev var: ${current.id}. Önce check_exam_task.';
    if (results.length == 0) throw "Puanlanmış görev yok.";
    var passed = 0, total = 0;
    for (result in results) {
      passed += result.passed;
      total += result.total;
    }
    var line : Dynamic = {
      date: DateTools.format(Date.now(), "%Y-%m-%d %H:%M"),
      model: args.model,
      game: commit("."),
      toolkit: commit("libs/scene-toolkit"),
      passed: passed,
      total: total,
      tasks: [for (result in results) {id: result.id, passed: result.passed, total: result.total, steps: result.steps, seconds: result.seconds,
        failed: [for (item in (result.checks : Array<Dynamic>)) if (!item.ok) item.check]}],
    };
    if (args.manual != null) line.manual = args.manual;
    if (args.note != null) line.note = args.note;
    var previous = last();
    if (!FileSystem.exists(DIRECTORY)) FileSystem.createDirectory(DIRECTORY);
    var output = File.append(RESULTS);
    output.writeString(haxe.Json.stringify(line) + "\n");
    output.close();
    results = [];
    return {result: line, previous: previous == null ? null : {date: previous.date, model: previous.model, passed: previous.passed, total: previous.total}, file: RESULTS};
  }

  // Hazırlık ve kontroller hazırlıktan önceki hale göre: hazırlığın bozduğu şey düzelmeden geçmez.
  function evaluate(spec : Dynamic, base : Baseline, origin : Baseline) : {ok : Bool, detail : String} {
    var created = [for (entity in editor.scene.entities) if (!base.entities.exists(entity.id)) entity];
    switch (spec.type) {
      case "created":
        var found = created.filter(entity -> matches(entity, spec.components, base) && (spec.near == null || within(entity, spec.near.entity, spec.near.distance)));
        var wanted : Int = spec.atLeast == null ? 1 : spec.atLeast;
        return {ok: found.length >= wanted, detail: '${found.length} uygun yeni nesne (${created.length} yeni)'};
      case "entity":
        var target = named(spec.name);
        if (target == null) return {ok: false, detail: '${spec.name} yok veya yüklü değil'};
        return {ok: matches(target, spec.components, base), detail: [for (c in target.components) describe(c)].join("; ")};
      case "model_file":
        // Model alanı katalog kimliği yazıyor ve kimlik bu dosyaya çıkıyor (kimliğin adı ajana bırakılır).
        var target = named(spec.name);
        if (target == null) return {ok: false, detail: '${spec.name} yok veya yüklü değil'};
        var found = component(target, spec.component);
        if (found == null) return {ok: false, detail: '${spec.component} bileşeni yok'};
        var value = Std.string(found.readField(spec.field));
        var file = scene.ModelRef.file(value);
        var ok = value != "" && !scene.ModelRef.isPath(value) && file == spec.file;
        return {ok: ok, detail: scene.ModelRef.isPath(value) ? 'alanda dosya yolu var: $value' : '$value → ${file == "" ? "(çözülmedi)" : file}'};
      case "walkable":
        var nav = editor.scene.service(NavWorld);
        var owners = created.filter(entity -> matches(entity, [{type: spec.component}], base));
        var blocked = owners.filter(entity -> !nav.isWalkable(entity.object.getAbsPos().tx, entity.object.getAbsPos().ty));
        return {ok: owners.length > 0 && blocked.length == 0, detail: owners.length == 0 ? '${spec.component} bileşenli yeni nesne yok' : blocked.length == 0 ? '${owners.length} nesne yürünebilir yerde' : 'yürünemez yerde: ${[for (e in blocked) e.name].join(", ")}'};
      case "quest_test":
        var fresh = [for (name in PlayTests.list()) if (base.tests.indexOf(name) < 0) name];
        if (fresh.length == 0) return {ok: false, detail: "res/tests altına yeni test yazılmadı"};
        var name = PlayTests.lastName;
        if (name == null || fresh.indexOf(name) < 0) return {ok: false, detail: 'yeni test (${fresh.join(", ")}) çalıştırılmadı'};
        var steps : Array<Dynamic> = try PlayTests.load(name).steps catch (e : Dynamic) [];
        if (spec.item != null && !Lambda.exists(steps, step -> step.expect != null && step.expect.item == spec.item))
          return {ok: false, detail: '$name testi ${spec.item} eşyasını beklemiyor'};
        // Beklentinin türü (örneğin oyunun "patrol" beklentisi): testte o türden bir expect adımı olmalı.
        if (spec.expect != null && !Lambda.exists(steps, step -> step.expect != null && Reflect.hasField(step.expect, spec.expect)))
          return {ok: false, detail: '$name testinde ${spec.expect} beklentisi yok'};
        // Adımın türü (örneğin oyunun "aid" adımı): testte o türden bir adım olmalı (sonucu beklemekle geçilmesin).
        if (spec.step != null && !Lambda.exists(steps, step -> Reflect.hasField(step, spec.step)))
          return {ok: false, detail: '$name testinde ${spec.step} adımı yok'};
        // Kayıttan başlayan test: oyuncunun kaydındaki hatayı yeniden üretip düzeltmeyi doğrulamak için.
        if (spec.save == true && (try PlayTests.load(name).save catch (e : Dynamic) null) == null)
          return {ok: false, detail: '$name testi bir kayıttan başlamıyor (save alanı yok)'};
        var result = PlayTests.result();
        if (result == null || FileSystem.stat(PlayFiles.RESULT).mtime.getTime() < base.wall - 1000) return {ok: false, detail: '$name için sonuç yok'};
        var failures : Array<String> = result.failures == null ? [] : result.failures;
        return {ok: result.passed == true, detail: result.passed == true ? '$name oyunda geçti' : '$name kaldı: ${failures.join("; ")}'};
      case "route_walkable", "route_near":
        var field : String = spec.field == null ? "route" : spec.field;
        var owners = created.filter(entity -> matches(entity, [{type: spec.component}], base));
        if (spec.ifAny == true) {
          owners = owners.filter(entity -> Std.string(component(entity, spec.component).readField(field)) != "");
          if (owners.length == 0) return {ok: true, detail: "rotalı yeni nesne yok"};
        }
        if (owners.length == 0) return {ok: false, detail: '${spec.component} bileşenli yeni nesne yok'};
        var problems = [];
        for (owner in owners) {
          var route = editor.scene.find(Std.string(component(owner, spec.component).readField(field)));
          if (route == null) {
            problems.push('${owner.name}: rota bağlı değil');
            continue;
          }
          var points = [for (child in route.children) child.object.getAbsPos()];
          if (spec.type == "route_walkable") {
            var nav = editor.scene.service(NavWorld);
            if (points.length < 2) problems.push('${route.name}: ${points.length} nokta');
            for (i in 0...points.length) {
              var point = points[i], next = points[(i + 1) % points.length];
              if (!nav.isWalkable(point.tx, point.ty)) problems.push('${route.name} ${i + 1}. nokta yürünemez');
              var path = nav.findPath(point.tx, point.ty, next.tx, next.ty);
              var end = path.length == 0 ? null : path[path.length - 1];
              if (i + 1 < points.length && (end == null || Math.abs(end.x - next.tx) + Math.abs(end.y - next.ty) > REACH)) problems.push('${route.name} ${i + 1}. noktadan sonrakine yol yok');
            }
          } else {
            var distance : Float = spec.distance == null ? 20 : spec.distance;
            for (name in [spec.from, spec.to]) {
              var at = positionOf(name);
              if (at == null) problems.push('$name yok');
              else if (!Lambda.exists(points, point -> Math.sqrt(Math.pow(point.tx - at[0], 2) + Math.pow(point.ty - at[1], 2)) <= distance))
                problems.push('${route.name} $name\'e $distance m yaklaşmıyor');
            }
          }
        }
        return {ok: problems.length == 0, detail: problems.length == 0 ? 'uygun' : problems.join("; ")};
      case "no_new_warnings":
        var fresh = [for (issue in editor.document.issues) if (!origin.issues.exists(issue.message)) issue.message];
        return {ok: fresh.length == 0, detail: fresh.length == 0 ? "yeni uyarı yok" : fresh.join("; ")};
      case "story_clean":
        var fresh = [for (found in StoryIndex.issues(StoryIndex.build(editor))) if (!origin.story.exists(found.message)) found.message];
        return {ok: fresh.length == 0, detail: fresh.length == 0 ? "hikâye bağları tam" : fresh.join("; ")};
      case "unchanged":
        var steps = editor.commands.undoCount - base.undoCount;
        return {ok: steps == 0, detail: steps == 0 ? "geçmişe adım eklenmedi" : '$steps adım eklendi'};
      // Görsel işte ajan sonucu gözle denetlemeli: görev başladıktan sonra bu araç başarıyla çağrıldı mı.
      case "tool_used":
        var calls = editor.agent.log.filter(entry -> entry.tool == spec.tool && entry.ok && entry.time >= base.wall).length;
        return {ok: calls > 0, detail: '${spec.tool} $calls kez çağrıldı'};
      case "max_steps":
        var steps = editor.commands.undoCount - base.undoCount;
        return {ok: steps >= 1 && steps <= spec.steps, detail: '$steps geri alma adımı'};
      case "camera":
        var orbit = editor.viewport.camera;
        var pitch = orbit.pitch * 180 / Math.PI;
        var factor = orbit.distance / base.camera.distance;
        var ok = (spec.maxPitchDegrees == null || pitch <= spec.maxPitchDegrees) && (spec.minDistanceFactor == null || factor >= spec.minDistanceFactor);
        return {ok: ok, detail: 'eğim ${Math.round(pitch)}°, uzaklık ×${Math.round(factor * 10) / 10}'};
      case "selection":
        var expected = [for (entity in editor.scene.entities) if (spec.component == null || matches(entity, [{type: spec.component}], base)) entity];
        var selected = editor.selection.items;
        var ok = expected.length > 0 && selected.length == expected.length && Lambda.foreach(expected, entity -> selected.indexOf(entity) >= 0);
        return {ok: ok, detail: '${selected.length} seçili, beklenen ${expected.length}'};
      case "table_rows":
        var table = editor.data.tables.get(spec.table);
        var before = base.rows.get(spec.table);
        var added = table == null ? [] : [for (id in table.ids()) if (before == null || before.indexOf(id) < 0) id];
        var wanted : Int = spec.added == null ? 1 : spec.added;
        return {ok: added.length >= wanted, detail: '${added.length} yeni satır: ${added.join(", ")}'};
      case "dialog_created":
        var types : Array<String> = spec.nodeTypes == null ? [] : spec.nodeTypes;
        // id verilirse o diyaloğa bakılır (hazırlıkta kurulan), yoksa görevde oluşturulanlara.
        var fresh = spec.id != null ? [for (id in editor.dialogs.ids()) if (id == spec.id) editor.dialogs.dialogs.get(id)]
          : [for (id in editor.dialogs.ids()) if (base.dialogs.indexOf(id) < 0) editor.dialogs.dialogs.get(id)];
        var ok = Lambda.exists(fresh, dialog -> Lambda.foreach(types, type -> Lambda.exists(dialog.nodes, node -> node.type == type)));
        return {ok: ok, detail: fresh.length == 0 ? "yeni diyalog yok" : [for (dialog in fresh) '${dialog.id}: ${[for (node in dialog.nodes) node.type].join(" ")}'].join("; ")};
      case "table_value":
        var table = editor.data.tables.get(spec.table);
        var row = table == null ? null : table.find(spec.row);
        var value : Dynamic = row == null ? null : row.get(spec.column);
        var ok = Std.isOfType(spec.value, Float) && Std.isOfType(value, Float) ? Math.abs((spec.value : Float) - (value : Float)) < 1e-6 : value == spec.value;
        return {ok: ok, detail: '${spec.table}.${spec.row}.${spec.column} = $value'};
      // Çeviri (docs/DIL_PLANI.md, D8): hücrenin bu dilde çevirisi var, eskimiş değil; differs true ise kaynak metinden farklı.
      case "translation":
        var source = TranslationStatus.source(editor, spec.table);
        var row = source == null ? null : source.find(spec.row);
        var original : Null<String> = row == null ? null : row.get(spec.column);
        var layer = TranslationStatus.reader(editor), text = layer.text(spec.language, spec.table, spec.row, spec.column);
        var stale = source != null && layer.audit(spec.language, source).stale.indexOf('${spec.row}.${spec.column}') >= 0;
        var ok = text != null && text != "" && !stale && (spec.differs != true || text != original);
        return {ok: ok, detail: '${spec.language}/${spec.table}/${spec.row}.${spec.column}: ${text == null ? "çeviri yok" : '"$text"'}'
          + (stale ? " (eskimiş)" : "") + ' (kaynak "$original")'};
      // Bir dilde bütün tablolar ve diyaloglar tam: eksik ve eskimiş çeviri yok.
      case "translations_complete":
        var left = [];
        for (report in TranslationStatus.report(editor, [spec.language]))
          for (key in report.missing.concat(report.stale)) left.push('${report.table}/$key');
        return {ok: left.length == 0, detail: left.length == 0 ? '${spec.language} tam' : '${left.length} kaldı: ${left.slice(0, 6).join(", ")}'};
      default:
        if (checks.exists(spec.type)) return checks.get(spec.type)(spec, created);
        throw 'bilinmeyen kontrol: ${spec.type}';
    }
  }

  // components: [{type, fields}] aynı nesnede. Alan değeri "$yeni" ise görevde oluşturulan bir şeyi göstermeli.
  function matches(entity : Entity, specs : Array<Dynamic>, base : Baseline) : Bool {
    for (spec in specs) {
      var found = component(entity, spec.type);
      if (found == null) return false;
      if (spec.fields == null) continue;
      for (name in Reflect.fields(spec.fields)) {
        var wanted : Dynamic = Reflect.field(spec.fields, name), actual : Dynamic = found.readField(name);
        if (wanted == NEW) {
          if (!isNew(Std.string(actual), base)) return false;
        } else if (Std.isOfType(wanted, Float) && Std.isOfType(actual, Float)) {
          if (Math.abs((wanted : Float) - (actual : Float)) > 1e-6) return false;
        } else if (actual != wanted) return false;
      }
    }
    return true;
  }

  function within(entity : Entity, name : String, distance : Float) : Bool {
    var b = positionOf(name);
    if (b == null) return false;
    var a = entity.object.getAbsPos();
    return Math.sqrt(Math.pow(a.tx - b[0], 2) + Math.pow(a.ty - b[1], 2)) <= distance;
  }

  // Yüklü nesne, yoksa yüklü olmayan hücrelerdeki kök nesne (diskten).
  function positionOf(name : String) : Null<Array<Float>> {
    var entity = named(name);
    if (entity != null) {
      var at = entity.object.getAbsPos();
      return [at.tx, at.ty];
    }
    var world = editor.document.world;
    if (world == null) return null;
    var wanted = name.toLowerCase();
    for (cell in world.data.cells()) {
      if (world.isLoaded(cell)) continue;
      var text = DiskGuard.read("res/" + world.data.path(cell, WorldData.OBJECTS_SUFFIX));
      if (text == null) continue;
      for (item in SceneFormat.read(text).entities)
        if (item.parent == null && (item.name.toLowerCase() == wanted || item.id == name)) return [item.position[0], item.position[1]];
    }
    return null;
  }

  static function describe(component : Component) : String {
    return '${component.componentId()} ${[for (field in component.describeFields()) '${field.name}=${component.readField(field.name)}'].join(" ")}';
  }

  // Hazırlıkta {"$near": ad, "offset": [x, y]} o nesnenin konumuna çevrilir.
  function prepare(value : Dynamic) : Dynamic {
    if (value == null || Std.isOfType(value, String) || Std.isOfType(value, Float) || Std.isOfType(value, Bool)) return value;
    if (Std.isOfType(value, Array)) return [for (item in (value : Array<Dynamic>)) prepare(item)];
    var near : Null<String> = Reflect.field(value, "$near");
    if (near != null) {
      var at = positionOf(near);
      if (at == null) throw '$near yok';
      var offset : Array<Float> = value.offset == null ? [0, 0] : value.offset;
      return [at[0] + offset[0], at[1] + offset[1]];
    }
    var copy : Dynamic = {};
    for (field in Reflect.fields(value)) Reflect.setField(copy, field, prepare(Reflect.field(value, field)));
    return copy;
  }

  function isNew(value : String, base : Baseline) : Bool {
    if (value == "") return false;
    if (base.dialogs.indexOf(value) < 0 && editor.dialogs.exists(value)) return true;
    if (!base.entities.exists(value) && editor.scene.find(value) != null) return true;
    for (name => ids in base.rows) if (ids.indexOf(value) < 0 && editor.data.exists(name, value)) return true;
    return false;
  }

  static function component(entity : Entity, type : String) : Null<Component> {
    return Lambda.find(entity.components, component -> component.componentId() == type);
  }

  function named(name : String) : Null<Entity> {
    var wanted = name.toLowerCase();
    return Lambda.find(editor.scene.entities, entity -> entity.name.toLowerCase() == wanted || entity.id == name);
  }

  function baseline() : Baseline {
    editor.document.validate();
    var orbit = editor.viewport.camera;
    return {
      time: haxe.Timer.stamp(),
      wall: Date.now().getTime(),
      clean: editor.document.unsavedFiles().length == 0,
      tests: PlayTests.list(),
      objectFiles: editor.document.world == null ? [] : editor.document.world.objectFiles(),
      navs: navFiles(editor.document.world == null ? [] : editor.document.world.objectFiles()),
      undoCount: editor.commands.undoCount,
      entities: [for (entity in editor.scene.entities) entity.id => true],
      issues: [for (issue in editor.document.issues) issue.message => true],
      story: [for (found in StoryIndex.issues(StoryIndex.build(editor))) found.message => true],
      rows: [for (name => table in editor.data.tables) name => table.ids()],
      dialogs: editor.dialogs.ids(),
      releaseList: FileSystem.exists(ReleaseIds.PATH) ? sys.io.File.getContent(ReleaseIds.PATH) : null,
      copied: [],
      copiedDirs: [],
      camera: {target: orbit.lookPoint(), distance: orbit.distance, yaw: orbit.yaw, pitch: orbit.pitch},
      selection: [for (entity in editor.selection.items) entity.id],
    };
  }

  // Geri alır; görev kaydettiyse ve önceden kaydedilmemiş iş yoksa disk de eski haline yazılır.
  // Görevde yazılan test dosyaları LEFTOVERS altına taşınır.
  // Görevin dosyaları (örneğin oyuncudan gelmiş bir kayıt): yerlerine kopyalanır, sınav sonunda yalnızca
  // sınavın koyduğu dosyalar ve açtığı boş klasörler silinir. Var olan dosyanın üstüne yazılmaz.
  function copyFiles(task : Dynamic, origin : Baseline) {
    var files : Array<Dynamic> = task.files == null ? [] : task.files;
    for (file in files) {
      var from : String = file.from, to : String = file.to;
      if (!FileSystem.exists(from)) throw 'sınav dosyası yok: $from';
      if (FileSystem.exists(to)) throw 'sınav dosyası zaten var, üstüne yazılmaz: $to';
      var missing = [], at = haxe.io.Path.directory(to);
      while (at != "" && !FileSystem.exists(at)) {
        missing.unshift(at);
        at = haxe.io.Path.directory(at);
      }
      for (dir in missing) {
        FileSystem.createDirectory(dir);
        origin.copiedDirs.push(dir);
      }
      File.copy(from, to);
      origin.copied.push(to);
    }
  }

  function restore(base : Baseline) : Dynamic {
    for (path in base.copied) if (FileSystem.exists(path)) FileSystem.deleteFile(path);
    var dirs = base.copiedDirs.copy();
    dirs.reverse();
    for (dir in dirs) if (FileSystem.exists(dir) && FileSystem.readDirectory(dir).length == 0) FileSystem.deleteDirectory(dir);
    while (editor.commands.undoCount > base.undoCount) editor.commands.undo();
    var saved = false, note : Null<String> = null, dropped = [], navRestored : Array<String> = [];
    if (editor.commands.isDirty) {
      if (base.clean) {
        saved = editor.document.save();
        var world = editor.document.world;
        if (saved && world != null)
          for (path in world.objectFiles()) if (base.objectFiles.indexOf(path) < 0 && world.dropEmptyObjectFile(path)) dropped.push('res/$path');
        // Görevin kaydı yol ağını yeniden üretmişse (yeni nesne hücreyi değiştirir) sınavdan önceki hali geri yazılır.
        if (saved && world != null) navRestored = restoreNavs(base, world.objectFiles().concat(base.objectFiles));
      } else note = "Görev sırasında kaydedildi; disk sınav öncesinden farklı. Kaydedersen senin halin yazılır.";
    }
    var releaseNow = FileSystem.exists(ReleaseIds.PATH) ? sys.io.File.getContent(ReleaseIds.PATH) : null;
    if (releaseNow != base.releaseList) {
      if (base.releaseList == null) FileSystem.deleteFile(ReleaseIds.PATH);
      else sys.io.File.saveContent(ReleaseIds.PATH, base.releaseList);
    }
    var moved = [];
    var fresh = [for (name in PlayTests.list()) if (base.tests.indexOf(name) < 0) name];
    if (fresh.length > 0) {
      var target = '$LEFTOVERS/${DateTools.format(Date.now(), "%Y%m%d-%H%M%S")}';
      if (!FileSystem.exists(target)) FileSystem.createDirectory(target);
      for (name in fresh) {
        var file = '$name${PlayFiles.TEST_SUFFIX}';
        FileSystem.rename('${PlayFiles.TESTS}/$file', '$target/$file');
        moved.push('$target/$file');
      }
    }
    editor.document.validate();
    editor.viewport.camera.place(base.camera.target, base.camera.distance, base.camera.yaw, base.camera.pitch);
    editor.selection.set([for (id in base.selection) if (editor.scene.find(id) != null) editor.scene.find(id)]);
    var result : Dynamic = {saved: saved, movedTests: moved, removedEmptyFiles: dropped};
    if (navRestored.length > 0) result.restoredNavFiles = navRestored;
    if (note != null) result.note = note;
    return result;
  }

  // Dünyanın klasörlerindeki yol ağı dosyaları ve içerikleri (yol res/ ile).
  static function navFiles(objectFiles : Array<String>) : Map<String, String> {
    var dirs = new Map<String, Bool>(), found = new Map<String, String>();
    for (path in objectFiles) dirs.set('res/' + haxe.io.Path.directory(path), true);
    for (dir in dirs.keys()) if (FileSystem.exists(dir) && FileSystem.isDirectory(dir))
      for (file in FileSystem.readDirectory(dir)) if (StringTools.endsWith(file, NAV_SUFFIX)) found.set('$dir/$file', File.getContent('$dir/$file'));
    return found;
  }

  // Değişen yol ağı dosyası sınavdan önceki haline, görevde oluşan silinir. Döner: dokunulan dosyalar.
  static function restoreNavs(base : Baseline, objectFiles : Array<String>) : Array<String> {
    var touched = [];
    for (path => text in navFiles(objectFiles)) {
      var before = base.navs.get(path);
      if (before == null) {
        FileSystem.deleteFile(path);
        touched.push(path);
      } else if (before != text) {
        File.saveContent(path, before);
        touched.push(path);
      }
    }
    for (path => text in base.navs) if (!FileSystem.exists(path)) {
      File.saveContent(path, text);
      touched.push(path);
    }
    return touched;
  }

  function ids() : Array<String> {
    if (!FileSystem.exists(DIRECTORY)) return [];
    var names = [for (file in FileSystem.readDirectory(DIRECTORY)) if (StringTools.endsWith(file, SUFFIX)) file.substr(0, file.length - SUFFIX.length)];
    names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    return names;
  }

  function read(id : String) : Dynamic {
    var path = '$DIRECTORY/$id$SUFFIX';
    if (!FileSystem.exists(path)) throw 'Sınav görevi yok: $id. Görevler: ${ids().join(", ")}';
    return haxe.Json.parse(File.getContent(path));
  }

  function last() : Dynamic {
    if (!FileSystem.exists(RESULTS)) return null;
    var lines = [for (line in File.getContent(RESULTS).split("\n")) if (StringTools.trim(line) != "") line];
    return lines.length == 0 ? null : try haxe.Json.parse(lines[lines.length - 1]) catch (e : Dynamic) null;
  }

  // Sonucun hangi sürüme ait olduğu: git'i çalıştırmadan HEAD okunur. Alt modülde .git bir dosyadır.
  static function commit(directory : String) : String {
    try {
      var git = '$directory/.git';
      if (!FileSystem.isDirectory(git)) git = haxe.io.Path.join([directory, StringTools.trim(StringTools.replace(File.getContent(git), "gitdir:", ""))]);
      var head = StringTools.trim(File.getContent('$git/HEAD'));
      if (!StringTools.startsWith(head, "ref: ")) return head.substr(0, 7);
      var ref = head.substr(5);
      if (FileSystem.exists('$git/$ref')) return StringTools.trim(File.getContent('$git/$ref')).substr(0, 7);
      for (line in File.getContent('$git/packed-refs').split("\n")) if (StringTools.endsWith(StringTools.trim(line), " " + ref)) return line.substr(0, 7);
    } catch (e : Dynamic) {}
    return "bilinmiyor";
  }
}

typedef Baseline = {
  time : Float,
  wall : Float,
  clean : Bool,
  tests : Array<String>,
  objectFiles : Array<String>,
  navs : Map<String, String>,
  undoCount : Int,
  entities : Map<String, Bool>,
  issues : Map<String, Bool>,
  story : Map<String, Bool>,
  rows : Map<String, Array<String>>,
  dialogs : Array<String>,
  camera : {target : Vec3, distance : Float, yaw : Float, pitch : Float},
  // Yayın listesi (res/kayit/kimlikler.json) dosya işidir, geri alma onu kapsamaz: sınav sonunda eski hali geri konur.
  releaseList : Null<String>,
  // Görevin kopyaladığı dosyalar ve açtığı klasörler (task.files): sınav sonunda silinir.
  copied : Array<String>,
  copiedDirs : Array<String>,
  selection : Array<String>,
};
