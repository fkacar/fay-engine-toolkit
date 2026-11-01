package scene.editor;

import h3d.mat.Texture;

// Asset Browser küçük resimleri. Ayrı sahnede çizilir, karede en fazla bir model
// yüklenir: büyük bir klasör açıldığında editör donmaz.
class ModelPreview {
  static inline var SIZE = 192;
  static inline var BACKGROUND = 0xFF34343A;

  var scene = new h3d.scene.Scene();
  var textures = new Map<String, Texture>();
  var queued = new Map<String, Bool>();
  var failures = new Map<String, String>();
  var queue : Array<String> = [];

  public function new() {
    var direction = new h3d.Vector(-0.5, 0.4, -0.8);
    var system = Std.downcast(scene.lightSystem, h3d.scene.fwd.LightSystem);
    if (system != null) {
      new h3d.scene.fwd.DirLight(direction, scene);
      system.ambientLight.set(0.55, 0.55, 0.55);
    } else {
      new h3d.scene.pbr.DirLight(direction, scene);
    }
    scene.camera.fovY = 30;
  }

  public function textureOf(path : String) : Null<Texture> {
    var texture = textures.get(path);
    if (texture == null && !failures.exists(path) && !queued.exists(path)) {
      queued.set(path, true);
      queue.push(path);
    }
    return texture;
  }

  public function failureOf(path : String) {
    return failures.get(path);
  }

  public function render(engine : h3d.Engine) {
    var path = queue.shift();
    if (path == null) return;
    queued.remove(path);
    var model = null;
    try {
      model = ModelLibrary.load(path);
    } catch (e : Dynamic) {
      failures.set(path, Std.string(e));
      return;
    }
    scene.addChild(model);
    frame(model);

    var texture = new Texture(SIZE, SIZE, [Target]);
    texture.depthBuffer = new Texture(SIZE, SIZE, [Target], Depth24Stencil8);
    scene.setOutputTarget(engine, texture);
    engine.clear(BACKGROUND, 1);
    scene.render(engine);
    scene.setOutputTarget();
    model.remove();
    textures.set(path, texture);
  }

  function frame(model : h3d.scene.Object) {
    var bounds = model.getBounds();
    var center = bounds.getCenter();
    var size = Math.max(Math.max(bounds.xSize, bounds.ySize), bounds.zSize);
    var camera = scene.camera;
    camera.target.set(center.x, center.y, center.z);
    camera.pos.set(center.x + size * 1.7, center.y - size * 1.7, center.z + size * 1.2);
    camera.zNear = size * 0.02;
    camera.zFar = size * 20;
    camera.update();
  }
}
