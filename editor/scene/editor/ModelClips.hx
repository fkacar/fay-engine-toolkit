package scene.editor;

import h3d.anim.LinearAnimation;
import hxd.fmt.hmd.Data;
import scene.editor.ImportSettings.ClipSpec;

typedef ClipInfo = {name : String, frames : Int, seconds : Float, loop : Bool, groundSpeed : Float, ?heading : Array<Float>};

typedef ClipSource = {spec : ClipSpec, hmd : Data, animation : Null<h3d.anim.Animation>};

// Karakter modeline başka FBX'lerden klip ekler ve ölçer. Klipler aynı iskeletten olmalıdır (örneğin
// Meshy'nin aynı gövdeden ürettikleri): oyunda eklemler adla bağlanır, modelde olmayan eklem atlanır.
// Adım hızı: yere basan ayağın kalçaya göre kayma hızı. Oyun yürüme ve koşmanın oynatma hızını buna
// göre ayarlar, ayak yerde kaymaz. describe() bütün uzunlukları metreye çevirir (modelin düğüm ölçeğiyle).
class ModelClips {
  // Ayak yere basıyor sayılır: en alçak noktasından boyun bu oranı kadar yukarıda değilse.
  static inline var PLANTED_FRACTION = 0.015;
  // Bu orandan çok eklemi modelde olmayan klip başka iskeletten gelmiştir.
  static inline var FOREIGN_FRACTION = 0.3;

  public static function merge(hmd : Data, clips : Array<ClipSource>, problems : Array<String>) : Array<ClipInfo> {
    var skin = skinOf(hmd);
    var names = skin == null ? new Map<String, Bool>() : [for (joint in skin.joints) joint.name => true];
    var height = heightOf(hmd);
    var out = new haxe.io.BytesOutput();
    out.write(hmd.data);
    if (hmd.animations == null) hmd.animations = [];
    var infos = [];
    for (clip in clips) {
      var animations = clip.hmd.animations == null ? [] : clip.hmd.animations;
      if (animations.length == 0) {
        problems.push('${clip.spec.source}: klip yok');
        continue;
      }
      var base = out.length;
      out.write(clip.hmd.data);
      for (k in 0...animations.length) {
        var animation = animations[k];
        var missing = animation.objects.filter(object -> !names.exists(object.name)).length;
        if (skin != null && missing > animation.objects.length * FOREIGN_FRACTION)
          problems.push('${clip.spec.source}: ${animation.objects.length} eklemin $missing tanesi modelde yok, klip başka iskeletten olabilir');
        animation.dataPosition += base;
        animation.name = k == 0 ? clip.spec.name : '${clip.spec.name}_${k + 1}';
        hmd.animations.push(animation);
        var step = k == 0 && clip.animation != null ? stepOf(hmd, clip.animation, height) : null;
        infos.push({
          name: animation.name,
          frames: animation.frames,
          seconds: round(animation.frames / animation.sampling),
          loop: animation.loop,
          groundSpeed: step == null ? 0. : round(step.speed),
          heading: step == null ? null : step.heading,
        });
      }
    }
    hmd.data = out.getBytes();
    return infos;
  }

  // Oyunun karakteri yerleştirmesi için: boy, birim, dinlenme pozunda kalçanın yeri, bakış yönü, klipler.
  public static function describe(hmd : Data, clips : Array<ClipInfo>) : Null<Dynamic> {
    var skin = skinOf(hmd);
    if (skin == null) return null;
    var scale = modelScale(hmd);
    var rest = restPose(skin.joints);
    var hips = indexOf(skin.joints, "Hips");
    if (hips < 0) hips = Lambda.findIndex(skin.joints, joint -> joint.parent < 0);
    var root = rest[hips];
    return {
      // Metre: modelin çizildiği boy, kalçanın dinlenme pozundaki yeri (başlangıç noktasına göre).
      height: round(heightOf(hmd) * scale),
      root: [round(root._41 * scale), round(root._42 * scale)],
      forward: forwardOf(clips, skin.joints, rest),
      clips: [for (clip in clips) {name: clip.name, frames: clip.frames, seconds: clip.seconds, loop: clip.loop, groundSpeed: round(clip.groundSpeed * scale)}],
    };
  }

  // Yürürken yere basan ayak geriye kayar: bakış yönü en hızlı klipte bunun tersidir. Klip yoksa
  // kalça çizgisine dik yön. Dosyanın varsayılan pozu bir klibin ilk karesi olabilir, gövde dönük durabilir.
  static function forwardOf(clips : Array<ClipInfo>, joints : Array<SkinJoint>, rest : Array<h3d.Matrix>) : Array<Float> {
    var fastest : Null<ClipInfo> = null;
    for (clip in clips) if (clip.heading != null && (fastest == null || clip.groundSpeed > fastest.groundSpeed)) fastest = clip;
    return fastest != null ? fastest.heading : forward(joints, rest);
  }

  static function forward(joints : Array<SkinJoint>, rest : Array<h3d.Matrix>) : Array<Float> {
    var left = indexOf(joints, "LeftUpLeg"), right = indexOf(joints, "RightUpLeg");
    if (left < 0 || right < 0) return [1., 0.];
    var sx = rest[left]._41 - rest[right]._41, sy = rest[left]._42 - rest[right]._42;
    var x = -sy, y = sx;
    var tx = 0., ty = 0.;
    for (pair in [["LeftFoot", "LeftToeBase"], ["RightFoot", "RightToeBase"]]) {
      var a = indexOf(joints, pair[0]), b = indexOf(joints, pair[1]);
      if (a < 0 || b < 0) continue;
      tx += rest[b]._41 - rest[a]._41;
      ty += rest[b]._42 - rest[a]._42;
    }
    if (x * tx + y * ty < 0) {
      x = -x;
      y = -y;
    }
    var length = Math.sqrt(x * x + y * y);
    return length < 1e-6 ? [1., 0.] : [round(x / length), round(y / length)];
  }

  // Heaps modeli düğüm ölçekleriyle çizer (Meshy'de 0,01: santimetre). Ölçekler metreye bu oranla çevrilir.
  static function modelScale(hmd : Data) : Float {
    var index = Lambda.findIndex(hmd.models, model -> model.skin != null);
    var scale = 1.;
    while (index >= 0) {
      scale *= hmd.models[index].position.sx;
      index = hmd.models[index].parent;
    }
    return scale;
  }

  static function stepOf(hmd : Data, animation : h3d.anim.Animation, height : Float) : Null<{speed : Float, heading : Null<Array<Float>>}> {
    var skin = skinOf(hmd);
    var linear = Std.downcast(animation, LinearAnimation);
    if (skin == null || linear == null) return null;
    var joints = skin.joints;
    var tracks = new Map<String, haxe.ds.Vector<LinearFrame>>();
    for (object in @:privateAccess linear.objects) {
      var track = Std.downcast(object, LinearObject);
      if (track != null && track.frames != null) tracks.set(object.objectName, track.frames);
    }
    var feet = [indexOf(joints, "LeftFoot"), indexOf(joints, "RightFoot")].filter(i -> i >= 0);
    if (feet.length == 0) return null;
    var order = depthOrder(joints);
    var world = [for (_ in joints) new h3d.Matrix()];
    var paths = [for (_ in feet) []];
    for (frame in 0...linear.frameCount) {
      for (i in order) {
        var track = tracks.get(joints[i].name);
        var local = track != null ? track[Std.int(Math.min(frame, track.length - 1))].toMatrix() : joints[i].position.toMatrix();
        if (joints[i].parent < 0) world[i].load(local) else world[i].multiply(local, world[joints[i].parent]);
      }
      for (k in 0...feet.length) paths[k].push(world[feet[k]].getPosition());
    }
    var speeds = [], sumX = 0., sumY = 0.;
    for (path in paths) {
      var lowest = 1e30;
      for (point in path) lowest = Math.min(lowest, point.z);
      var limit = lowest + height * PLANTED_FRACTION;
      for (i in 1...path.length)
        if (path[i].z <= limit && path[i - 1].z <= limit) {
          var dx = path[i].x - path[i - 1].x, dy = path[i].y - path[i - 1].y;
          speeds.push(Math.sqrt(dx * dx + dy * dy) * linear.sampling);
          sumX += dx;
          sumY += dy;
        }
    }
    if (speeds.length == 0) return {speed: 0, heading: null};
    speeds.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    var length = Math.sqrt(sumX * sumX + sumY * sumY);
    var speed = speeds[Std.int(speeds.length / 2)];
    // Yerinde duran klipte ayak kaymaz: yön anlamsızdır.
    var moving = speed > height * 0.05;
    return {speed: moving ? speed : 0, heading: moving && length > 1e-6 ? [round(-sumX / length), round(-sumY / length)] : null};
  }

  static function restPose(joints : Array<SkinJoint>) : Array<h3d.Matrix> {
    var world = [for (_ in joints) new h3d.Matrix()];
    for (i in depthOrder(joints)) {
      var local = joints[i].position.toMatrix();
      if (joints[i].parent < 0) world[i].load(local) else world[i].multiply(local, world[joints[i].parent]);
    }
    return world;
  }

  // Ebeveyn her zaman çocuğundan önce hesaplanır.
  static function depthOrder(joints : Array<SkinJoint>) : Array<Int> {
    function depth(i : Int) {
      var d = 0;
      while (joints[i].parent >= 0) {
        i = joints[i].parent;
        d++;
      }
      return d;
    }
    var order = [for (i in 0...joints.length) i];
    order.sort((a, b) -> depth(a) - depth(b));
    return order;
  }

  static function skinOf(hmd : Data) : Null<Skin> {
    for (model in hmd.models) if (model.skin != null) return model.skin;
    return null;
  }

  static function heightOf(hmd : Data) : Float {
    var bounds = ModelTrim.bounds(hmd);
    return bounds.max[2] - bounds.min[2];
  }

  static function indexOf(joints : Array<SkinJoint>, name : String) : Int {
    for (i in 0...joints.length) if (joints[i].name == name) return i;
    return -1;
  }

  static function round(value : Float) : Float {
    return Math.round(value * 1000) / 1000;
  }
}
