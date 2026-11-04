import components.GameComponents;
import scene.FocusGuard;
import scene.HiDpi;
import scene.PlayOptions;
import scene.SceneInstance;
import scene.SceneMode;
import scene.data.SceneFormat;
#if scene_editor
import scene.editor.Editor;
import scene.editor.FrameGuard;
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
    // Kare koruması: editörde bir kare yarıda kalırsa editör kapanmaz (scene.editor.FrameGuard).
    FrameGuard.install();
    #end
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
  override function mainLoop() {
    var failure = FrameGuard.beforeFrame();
    if (failure != null && editor != null) editor.frameFailed(failure);
    super.mainLoop();
  }

  override function render(e : h3d.Engine) {
    if (editor == null) {
      super.render(e);
      return;
    }
    var failure = FrameGuard.run(() -> editor.render(e));
    if (failure != null) editor.failed("Önizleme çizimi", failure);
    try {
      super.render(e);
    } catch (error : haxe.Exception) {
      editor.renderFailed(e, error, () -> {
        imgui.ImGui.render();
        @:privateAccess imguiScene.render(e);
      });
    }
    failure = FrameGuard.run(() -> editor.afterRender(e));
    if (failure != null) editor.failed("Çizim sonrası", failure);
  }
  #end

  override function update(dt : Float) {
    #if scene_editor
    if (editor != null) {
      var failure = FrameGuard.run(editor.draw);
      if (failure != null) editor.failed("Oyun", failure);
      return;
    }
    #end
    level.update(dt);
  }

  static function main() {
    new Main();
  }
}
