import components.GameComponents;
import scene.FocusGuard;
import scene.HiDpi;
import scene.PlayOptions;
import scene.SceneInstance;
import scene.SceneMode;
import scene.data.SceneFormat;
#if scene_editor
import scene.editor.Editor;
#end

class Main extends #if scene_editor imgui.ImGuiApp #else hxd.App #end {
  static inline var MAIN_SCENE = "scenes/main.scene.json";

  var level : SceneInstance;
  #if scene_editor
  var editor : Editor;
  #end

  override function init() {
    super.init();
    HiDpi.fit(s2d);
    #if scene_editor
    hxd.Res.initLocal();
    #else
    hxd.Res.initEmbed();
    #end

    new h3d.scene.fwd.DirLight(new h3d.Vector(-0.5, -0.4, -0.8), s3d);
    s3d.camera.pos.set(8, 8, 6);
    s3d.camera.target.set(0, 0, 0);

    // Editör ikilisi `--play` ile oyun olarak açılır: "Buradan oyna" böyle çalışır.
    var play = PlayOptions.parse(Sys.args());
    var editing = #if scene_editor play == null #else false #end;
    level = new SceneInstance(GameComponents.registry(), editing ? SceneMode.Editor : SceneMode.Game, s3d);
    level.prefabLoader = path -> hxd.Res.load(path).toText();
    level.load(SceneFormat.read(hxd.Res.load(play == null ? MAIN_SCENE : play.scene).toText()));

    #if scene_editor
    if (editing) {
      editor = new Editor(level, "res/" + MAIN_SCENE);
      editor.actions.addAssetType("fbx", "model", "path");
      editor.actions.addAssetType("hmd", "model", "path");
      return;
    }
    #end
    FocusGuard.install();
    level.start();
    if (play != null && play.camera != null) {
      s3d.camera.pos.set(play.camera[0], play.camera[1], play.camera[2]);
      s3d.camera.target.set(play.camera[3], play.camera[4], play.camera[5]);
    }
  }

  #if scene_editor
  override function render(e : h3d.Engine) {
    if (editor != null) editor.render(e);
    super.render(e);
    if (editor != null) editor.afterRender(e);
  }
  #end

  override function update(dt : Float) {
    #if scene_editor
    if (editor != null) {
      editor.draw();
      return;
    }
    #end
    level.update(dt);
  }

  static function main() {
    new Main();
  }
}
