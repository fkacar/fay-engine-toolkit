package scene.editor;

import haxe.DynamicAccess;
import sys.FileSystem;
import sys.io.File;

// Kişiye özel editör ayarları. `.editor/` git'e girmez, tasarımcılar birbirini etkilemez.
class EditorPrefs {
  public static inline var DIRECTORY = ".editor";

  static inline var FILE = DIRECTORY + "/prefs.json";
  static inline var MAX_RECENT = 8;

  public var recent(default, null) : Array<String> = [];

  var hidden : DynamicAccess<Array<String>> = {};
  var locked : DynamicAccess<Array<String>> = {};

  public function new() {
    if (!FileSystem.exists(FILE)) return;
    try {
      var saved = haxe.Json.parse(File.getContent(FILE));
      if (saved.recent != null) recent = saved.recent;
      if (saved.hidden != null) hidden = saved.hidden;
      if (saved.locked != null) locked = saved.locked;
    } catch (e : Dynamic) {
      // Bozuk ayar dosyası editörü durdurmamalı, varsayılanlarla devam edilir.
    }
  }

  public function addRecent(path : String) {
    recent.remove(path);
    recent.unshift(path);
    recent = recent.slice(0, MAX_RECENT);
    save();
  }

  public function removeRecent(path : String) {
    recent.remove(path);
    save();
  }

  public function hiddenIn(scene : String) : Array<String> {
    var ids = hidden.get(scene);
    return ids == null ? [] : ids;
  }

  public function lockedIn(scene : String) : Array<String> {
    var ids = locked.get(scene);
    return ids == null ? [] : ids;
  }

  public function setFlags(scene : String, hiddenIds : Array<String>, lockedIds : Array<String>) {
    store(hidden, scene, hiddenIds);
    store(locked, scene, lockedIds);
    save();
  }

  static function store(flags : DynamicAccess<Array<String>>, scene : String, ids : Array<String>) {
    if (ids.length == 0) flags.remove(scene);
    else flags.set(scene, ids);
  }

  function save() {
    if (!FileSystem.exists(DIRECTORY)) FileSystem.createDirectory(DIRECTORY);
    File.saveContent(FILE, haxe.Json.stringify({recent: recent, hidden: hidden, locked: locked}, null, "  "));
  }
}
