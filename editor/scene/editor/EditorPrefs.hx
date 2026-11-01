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
  public var layoutVersion(default, null) = 0;
  public var hiddenMarkers(default, null) : Array<String> = [];

  var hidden : DynamicAccess<Array<String>> = {};
  var groups : DynamicAccess<Array<Array<String>>> = {};

  public function new() {
    if (!FileSystem.exists(FILE)) return;
    try {
      var saved = haxe.Json.parse(File.getContent(FILE));
      if (saved.recent != null) recent = saved.recent;
      if (saved.hidden != null) hidden = saved.hidden;
      if (saved.groups != null) groups = saved.groups;
      if (saved.layoutVersion != null) layoutVersion = saved.layoutVersion;
      if (saved.hiddenMarkers != null) hiddenMarkers = saved.hiddenMarkers;
    } catch (e : Dynamic) {
      // Bozuk ayar dosyası editörü durdurmamalı, varsayılanlarla devam edilir.
    }
  }

  public function setHiddenMarkers(types : Array<String>) {
    hiddenMarkers = types;
    save();
  }

  public function setLayoutVersion(version : Int) {
    layoutVersion = version;
    save();
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

  public function groupsIn(scene : String) : Array<Array<String>> {
    var saved = groups.get(scene);
    return saved == null ? [] : saved;
  }

  public function setFlags(scene : String, hiddenIds : Array<String>, groupIds : Array<Array<String>>) {
    if (hiddenIds.length == 0) hidden.remove(scene);
    else hidden.set(scene, hiddenIds);
    if (groupIds.length == 0) groups.remove(scene);
    else groups.set(scene, groupIds);
    save();
  }

  function save() {
    if (!FileSystem.exists(DIRECTORY)) FileSystem.createDirectory(DIRECTORY);
    File.saveContent(FILE, haxe.Json.stringify({recent: recent, hidden: hidden, groups: groups, layoutVersion: layoutVersion, hiddenMarkers: hiddenMarkers}, null, "  "));
  }
}
