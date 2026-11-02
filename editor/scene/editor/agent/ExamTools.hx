package scene.editor.agent;

import scene.Entity;
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
  public static inline var RESULTS = "tests/ajan-sinavi/sonuclar.jsonl";
  public static inline var NEW = "$yeni";
  static inline var REACH = 2.;

  var editor : Editor;
  var current : Null<{id : String, task : Dynamic, base : Baseline}>;
  var results : Array<Dynamic> = [];

  public function new(editor : Editor, server : AgentServer) {
    this.editor = editor;
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
      text: args -> (args.elle == null || args.elle == "" ? "" : 'Elle puanlar: ${args.elle}. Bunları finish_exam\'in manual alanına yaz. ') + "Ajan sınavı. list_exam ile görevleri al. Her görev için sırayla start_exam_task ile başlat; görevi tasarımcı istemiş gibi yalnızca editör araçlarıyla yap, soru sorma, kaydetme; bitince check_exam_task çağır. Araç puanlar ve değişikliklerini geri alır. Hepsi bitince finish_exam'e model adını ver. Sonucu görev başına puanla bir tablo olarak göster, önceki sonuçla farkı ve kalan kontrolleri söyle."});
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
    current = {id: id, task: task, base: baseline()};
    return {id: id, title: task.title, prompt: task.prompt};
  }

  function check() : Dynamic {
    if (current == null) throw "Açık görev yok. Önce start_exam_task.";
    var task = current.task, base = current.base;
    editor.document.validate();
    var checks : Array<Dynamic> = task.checks;
    var outcome = [for (spec in checks) {
      var result = try evaluate(spec, base) catch (e : Dynamic) {ok: false, detail: 'denetlenemedi: $e'};
      {check: spec.label != null ? spec.label : spec.type, ok: result.ok, detail: result.detail};
    }];
    var steps = editor.commands.undoCount - base.undoCount;
    var seconds = Math.round(haxe.Timer.stamp() - base.time);
    restore(base);
    var passed = outcome.filter(item -> item.ok).length;
    var result = {id: current.id, passed: passed, total: outcome.length, steps: steps, seconds: seconds, checks: outcome};
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

  function evaluate(spec : Dynamic, base : Baseline) : {ok : Bool, detail : String} {
    var created = [for (entity in editor.scene.entities) if (!base.entities.exists(entity.id)) entity];
    switch (spec.type) {
      case "created":
        var found = created.filter(entity -> matches(entity, spec.components, base) && (spec.near == null || within(entity, spec.near.entity, spec.near.distance)));
        var wanted : Int = spec.atLeast == null ? 1 : spec.atLeast;
        return {ok: found.length >= wanted, detail: '${found.length} uygun yeni nesne (${created.length} yeni)'};
      case "route_walkable", "route_near":
        var owners = created.filter(entity -> matches(entity, [{type: spec.component}], base));
        if (owners.length == 0) return {ok: false, detail: '${spec.component} bileşenli yeni nesne yok'};
        var field : String = spec.field == null ? "route" : spec.field;
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
              var target = named(name);
              if (target == null) problems.push('$name yok');
              else {
                var at = target.object.getAbsPos();
                if (!Lambda.exists(points, point -> Math.sqrt(Math.pow(point.tx - at.tx, 2) + Math.pow(point.ty - at.ty, 2)) <= distance))
                  problems.push('${route.name} $name\'e $distance m yaklaşmıyor');
              }
            }
          }
        }
        return {ok: problems.length == 0, detail: problems.length == 0 ? 'uygun' : problems.join("; ")};
      case "no_new_warnings":
        var fresh = [for (issue in editor.document.issues) if (!base.issues.exists(issue.message)) issue.message];
        return {ok: fresh.length == 0, detail: fresh.length == 0 ? "yeni uyarı yok" : fresh.join("; ")};
      case "story_clean":
        var fresh = [for (found in StoryIndex.issues(StoryIndex.build(editor))) if (!base.story.exists(found.message)) found.message];
        return {ok: fresh.length == 0, detail: fresh.length == 0 ? "hikâye bağları tam" : fresh.join("; ")};
      case "unchanged":
        var steps = editor.commands.undoCount - base.undoCount;
        return {ok: steps == 0, detail: steps == 0 ? "geçmişe adım eklenmedi" : '$steps adım eklendi'};
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
        var fresh = [for (id in editor.dialogs.ids()) if (base.dialogs.indexOf(id) < 0) editor.dialogs.dialogs.get(id)];
        var ok = Lambda.exists(fresh, dialog -> Lambda.foreach(types, type -> Lambda.exists(dialog.nodes, node -> node.type == type)));
        return {ok: ok, detail: fresh.length == 0 ? "yeni diyalog yok" : [for (dialog in fresh) '${dialog.id}: ${[for (node in dialog.nodes) node.type].join(" ")}'].join("; ")};
      default:
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
    var target = named(name);
    if (target == null) return false;
    var a = entity.object.getAbsPos(), b = target.object.getAbsPos();
    return Math.sqrt(Math.pow(a.tx - b.tx, 2) + Math.pow(a.ty - b.ty, 2)) <= distance;
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
      undoCount: editor.commands.undoCount,
      entities: [for (entity in editor.scene.entities) entity.id => true],
      issues: [for (issue in editor.document.issues) issue.message => true],
      story: [for (found in StoryIndex.issues(StoryIndex.build(editor))) found.message => true],
      rows: [for (name => table in editor.data.tables) name => table.ids()],
      dialogs: editor.dialogs.ids(),
      camera: {target: orbit.lookPoint(), distance: orbit.distance, yaw: orbit.yaw, pitch: orbit.pitch},
      selection: [for (entity in editor.selection.items) entity.id],
    };
  }

  function restore(base : Baseline) {
    while (editor.commands.undoCount > base.undoCount) editor.commands.undo();
    editor.document.validate();
    editor.viewport.camera.place(base.camera.target, base.camera.distance, base.camera.yaw, base.camera.pitch);
    editor.selection.set([for (id in base.selection) if (editor.scene.find(id) != null) editor.scene.find(id)]);
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
  undoCount : Int,
  entities : Map<String, Bool>,
  issues : Map<String, Bool>,
  story : Map<String, Bool>,
  rows : Map<String, Array<String>>,
  dialogs : Array<String>,
  camera : {target : Vec3, distance : Float, yaw : Float, pitch : Float},
  selection : Array<String>,
};
