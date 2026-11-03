package scene.editor.agent;

import scene.PlayFiles;
import scene.editor.agent.AgentServer.AgentReply;
import sys.FileSystem;
import sys.io.File;

// Faz B: oyun gözü. Editörden açılan oyun durumunu ve hikâye izini bin/ajan altına yazar; görev
// testi oyunda oynanır, sonucu ve izi döner.
class PlayTools {
  static inline var TRACE_LIMIT = 80;
  static inline var EXTRA_SECONDS = 40.;
  static inline var DEFAULT_TIMEOUT = 120.;

  var editor : Editor;

  public function new(editor : Editor, server : AgentServer) {
    this.editor = editor;
    server.add({name: "get_game_state", readOnly: true,
      description: "Editörden açılan oyunun (F5 veya görev testi) o anki durumu: eşyalar, değişkenler, fraksiyon ilişkileri, açık diyalog ve seçenekleri, son bildirimler, ekip birimlerinin konumu ve yürüyüp yürümediği, NPC grupları, oyun kamerası ve oyunun eklediği alanlar (örneğin otomatik kaydın durumu). Oyun saniyede dört kez yazar.",
      schema: {type: "object", properties: {}},
      run: _ -> ({value: state()} : AgentReply)});
    server.add({name: "get_game_trace", readOnly: true,
      description: "Oyunun hikâye izi, en yeniden geriye: tetikleyici (çalıştı ve eylemleri), kosul_tutmadi (hangi koşul, alanları), olay (yayılan ve bekleyenler), diyalog, satir, secenekler, secim, diyalog_bitti, esya, degisken, iliski, mesaj, takildi (yürüyüp ilerleyemeyen birim).",
      schema: {type: "object", properties: {limit: {type: "integer"}, type: {type: "string", description: "Yalnızca bu türdeki kayıtlar"}}},
      run: args -> ({value: readTrace(args.limit == null ? TRACE_LIMIT : args.limit, args.type)} : AgentReply)});
    server.add({name: "list_quest_tests", readOnly: true,
      description: "res/tests altındaki görev testleri. Biçim kılavuzda: title, start {near, distance}, save (isteğe bağlı kayıt dosyası: test o kayıttan başlar), timeout ve steps (walkTo, waitDialog, advance, choose, wait, expect {item|flag|standing|fired|dialogOpen|message, atLeast|equals|atMost}).",
      schema: {type: "object", properties: {}},
      run: _ -> ({value: [for (name in PlayTests.list()) {name: name, test: PlayTests.load(name)}]} : AgentReply)});
    server.add({name: "run_quest_test", readOnly: true,
      description: "Kaydedilmiş bir görev testini oyunda oynar, bitince sonucu (adım adım), oyunun son durumunu ve izi döner. Dünya kayıtlı haliyle açılır; kaydedilmemiş değişiklikler teste girmez. Testte save varsa oyun o kayıttan açılır (hata ayıklama kopyası). Oyun ayrı pencerede açılıp kapanır.",
      schema: {type: "object", properties: {name: {type: "string"}}, required: ["name"]},
      run: args -> {
        var test = PlayTests.load(args.name);
        if (test == null) throw 'Görev testi yok veya okunamadı: ${args.name}. Testler: ${PlayTests.list().join(", ")}';
        var reply = run(test);
        PlayTests.lastName = args.name;
        return reply;
      }});
    server.add({name: "playtest", readOnly: true,
      description: "Kaydedilmemiş bir görev testi tarifini oyunda oynar (run_quest_test ile aynı biçim, steps zorunlu). Ne olduğunu denemek ve bir hatayı yeniden üretmek için. Dünya kayıtlı haliyle açılır; save verilirse o kayıttan (list_saves).",
      schema: {type: "object", properties: {
        title: {type: "string"},
        save: {type: "string", description: "Kayıt dosyasının yolu (list_saves): oyun o kayıttan başlar, asıl dosyaya yazılmaz"},
        start: {type: "object", description: "{near: nesne adı, distance: metre} veya {at: [x, y]}"},
        steps: {type: "array", items: {type: "object"}},
        timeout: {type: "number"},
      }, required: ["steps"]},
      run: args -> {
        var reply = run(args);
        PlayTests.lastName = null;
        return reply;
      }});
  }

  function run(test : Dynamic) : AgentReply {
    var unsaved = editor.document.unsavedFiles();
    var problem = editor.startPlayTest(test, false);
    if (problem != null) throw problem;
    var limit : Float = (test.timeout != null ? test.timeout : DEFAULT_TIMEOUT) / 3 + EXTRA_SECONDS;
    var begun = haxe.Timer.stamp();
    return {
      timeout: limit,
      wait: () -> {
        var result = PlayTests.result();
        if (result != null) {
          if (unsaved.length > 0) result.note = 'Kaydedilmemiş değişiklikler teste girmedi: ${unsaved.join(", ")}';
          return {value: result};
        }
        // Oyun sonuç yazmadan kapandıysa günlüğün sonu döner.
        if (!editor.isPlaying() && haxe.Timer.stamp() - begun > 2) return {text: 'Oyun sonuç yazmadan kapandı. bin/play.log: ${tail("bin/play.log", 8)}'};
        return null;
      },
    };
  }

  function state() : Dynamic {
    if (!FileSystem.exists(PlayFiles.STATE)) throw "Oyun durumu yok: oyun editörden (F5 veya görev testi) açılmadı";
    var age = Date.now().getTime() - FileSystem.stat(PlayFiles.STATE).mtime.getTime();
    var value : Dynamic = haxe.Json.parse(File.getContent(PlayFiles.STATE));
    value.running = editor.isPlaying();
    value.ageSeconds = Math.round(age / 100) / 10;
    return value;
  }

  function readTrace(limit : Int, type : Null<String>) : Dynamic {
    if (!FileSystem.exists(PlayFiles.TRACE)) throw "İz yok: oyun editörden açılmadı";
    var lines = StringTools.trim(File.getContent(PlayFiles.TRACE)).split("\n").filter(line -> line != "");
    var entries : Array<Dynamic> = [for (line in lines) try haxe.Json.parse(line) catch (e : Dynamic) null].filter(entry -> entry != null);
    if (type != null) entries = entries.filter(entry -> entry.type == type);
    return {running: editor.isPlaying(), total: entries.length, entries: entries.slice(-limit)};
  }

  static function tail(path : String, count : Int) {
    if (!FileSystem.exists(path)) return "(yok)";
    return StringTools.trim(File.getContent(path)).split("\n").slice(-count).join(" / ");
  }
}
