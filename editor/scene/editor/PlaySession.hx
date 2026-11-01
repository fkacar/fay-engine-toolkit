package scene.editor;

import scene.PlayOptions;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

// "Buradan oyna" ayrı süreçte çalışır: durum sızmaz, oyun çökerse editör etkilenmez.
// Editörün kendi ikilisi kullanılır, çünkü oyun derlemesi kaynakları gömülü taşır ve
// yeni kaydedilen sahneyi veya modeli görmez.
class PlaySession {
  static inline var LOG = "bin/play.log";
  static inline var LOG_LINES = 6;

  public var isRunning(get, never) : Bool;

  var process : Null<Process>;

  public function new() {}

  public function start(options : PlayOptions) {
    var args = [for (arg in options.toArgs()) arg.indexOf(" ") >= 0 ? '"$arg"' : arg].join(" ");
    #if hlc
    process = new Process('exec "${Sys.programPath()}" $args > $LOG 2>&1');
    #else
    process = new Process('.hashlink\\hl.exe bin\\editor.hl $args > bin\\play.log 2>&1');
    #end
  }

  // Oyun hatayla kapanınca günlüğün sonunu döndürür.
  public function poll() : Null<String> {
    if (process == null) return null;
    var code = process.exitCode(false);
    if (code == null) return null;
    process.close();
    process = null;
    if (code == 0) return null;
    return 'Oyun hatayla kapandı ($code): ${logTail()}';
  }

  function logTail() {
    if (!FileSystem.exists(LOG)) return "";
    var lines = StringTools.trim(File.getContent(LOG)).split("\n");
    return lines.slice(-LOG_LINES).join(" / ");
  }

  function get_isRunning() {
    return process != null;
  }
}
