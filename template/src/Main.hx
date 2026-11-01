import components.GameComponents;
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
    #if scene_editor
    hxd.Res.initLocal();
    #else
    hxd.Res.initEmbed();
    #end

    new h3d.scene.fwd.DirLight(new h3d.Vector(-0.5, -0.4, -0.8), s3d);
    s3d.camera.pos.set(8, 8, 6);
    s3d.camera.target.set(0, 0, 0);

    var mode = #if scene_editor SceneMode.Editor #else SceneMode.Game #end;
    level = new SceneInstance(GameComponents.registry(), mode, s3d);
    level.load(SceneFormat.read(hxd.Res.load(MAIN_SCENE).toText()));

    #if scene_editor
    editor = new Editor(level, "res/" + MAIN_SCENE);
    #else
    level.start();
    #end
  }

  override function update(dt : Float) {
    #if scene_editor
    editor.draw();
    #else
    level.update(dt);
    #end
  }

  static function main() {
    new Main();
  }
}
