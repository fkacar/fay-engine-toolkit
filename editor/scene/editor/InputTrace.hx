package scene.editor;

import sys.FileSystem;
import sys.io.File;

// Son girdi durumlarının kısa kaydı. Yalnızca değişiklikler tutulur, bellek büyümez.
class InputTrace {
  static inline var FILE = EditorPrefs.DIRECTORY + "/girdi-kaydi.txt";
  static inline var MAX_LINES = 800;

  var lines : Array<String> = [];
  var last = "";

  public function new() {}

  public function record(state : String) {
    if (state == last) return;
    last = state;
    lines.push(DateTools.format(Date.now(), "%H:%M:%S") + " " + state);
    if (lines.length > MAX_LINES) lines.shift();
  }

  public function write() {
    if (!FileSystem.exists(EditorPrefs.DIRECTORY)) FileSystem.createDirectory(EditorPrefs.DIRECTORY);
    File.saveContent(FILE, lines.join("\n") + "\n");
    return FILE;
  }
}
