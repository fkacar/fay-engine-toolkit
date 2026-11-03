package scene.editor;

import h3d.anim.LinearAnimation;
import hxd.fmt.hmd.Data;
import scene.editor.ImportSettings.ClipSpec;
import scene.editor.ImportSettings.SocketSpec;

typedef ClipInfo = {name : String, frames : Int, seconds : Float, loop : Bool, groundSpeed : Float, ?heading : Array<Float>, ?retargeted : Int};

typedef ClipSource = {spec : ClipSpec, hmd : Data, animation : Null<h3d.anim.Animation>, ?retargeted : Int};

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
          retargeted: clip.retargeted,
        });
      }
    }
    hmd.data = out.getBytes();
    return infos;
  }

  // Oyunun karakteri yerleştirmesi için: boy, birim, dinlenme pozunda kalçanın yeri, bakış yönü, klipler.
  // İskeletsiz modelde (silah, eşya) yalnızca takma noktaları yazılır, o da varsa.
  public static function describe(hmd : Data, clips : Array<ClipInfo>, ?sockets : Array<SocketSpec>) : Null<Dynamic> {
    if (sockets == null) sockets = [];
    var skin = skinOf(hmd);
    if (skin == null) return sockets.length == 0 ? null : {sockets: sockets};
    var scale = modelScale(hmd);
    var rest = restPose(skin.joints);
    var hips = indexOf(skin.joints, "Hips");
    if (hips < 0) hips = Lambda.findIndex(skin.joints, joint -> joint.parent < 0);
    var root = rest[hips];
    var facing = forwardOf(clips, skin.joints, rest);
    // Takma noktalarının ekseni: bağlama pozundaki gövdenin önü (ayak parmaklarının yönü). Kliplerin
    // yönü bundan farklı olabilir (dinlenme pozu ters dönük bir klip karesi olabilir); köşeler bağlama pozuna bağlı.
    var bind = bindPose(skin.joints);
    var frame = forward(skin.joints, [for (i in 0...skin.joints.length) bind[i] != null ? bind[i] : rest[i]]);
    return {
      // Metre: modelin çizildiği boy, kalçanın dinlenme pozundaki yeri (başlangıç noktasına göre).
      height: round(heightOf(hmd) * scale),
      root: [round(root._41 * scale), round(root._42 * scale)],
      forward: facing,
      clips: [for (clip in clips) {name: clip.name, frames: clip.frames, seconds: clip.seconds, loop: clip.loop, groundSpeed: round(clip.groundSpeed * scale)}],
      socketFrame: frame,
      sockets: sockets.length > 0 ? sockets : defaultSockets(hmd, skin.joints, frame, scale),
    };
  }

  // Ayar yoksa Mixamo düzenindeki eklemlere takma noktaları. El noktasının X'i bilekten parmaklara
  // (ön kol yönünde), Z'si yumruğun deliği boyunca başparmağa: A pozunda başparmak öne bakar.
  // Avuç, ele bağlı köşelerin bileğe yakın yarısının bağlama pozundaki ortası (uzun parmak ve pençe avucu
  // uca kaydırmasın); köşe okunamazsa bileğin ön kol boyunun üçte biri
  // ilerisi. Konumlar ve eksenler bağlama pozuna göredir (deri köşeleri ona bağlıdır): X gövdenin önü
  // (frame), Z yukarı, Y sağ. Dönüş oyunla aynı Heaps nesnesiyle hesaplanır.
  public static function defaultSockets(hmd : Data, joints : Array<SkinJoint>, facing : Array<Float>, scale : Float) : Array<SocketSpec> {
    var bind = bindPose(joints), rest = restPose(joints);
    var pose = [for (i in 0...joints.length) bind[i] != null ? bind[i] : rest[i]];
    var turn = new h3d.scene.Object();
    turn.setRotation(0, 0, -Math.atan2(facing[1], facing[0]));
    var toFacingMatrix = turn.getAbsPos().clone();
    function toFacing(x : Float, y : Float, z : Float) return new h3d.Vector(x, y, z).transformed3x3(toFacingMatrix);
    var found = [];
    function hand(name : String, joint : String, arm : String) {
      var a = indexOf(joints, arm), b = indexOf(joints, joint);
      if (a < 0 || b < 0) return;
      var wrist = pose[b].getPosition();
      var palm = palmOf(boneVertices(hmd, b), wrist);
      var reach = 0.;
      var along = if (palm != null) {
        var d = palm.sub(wrist);
        reach = d.length() * scale;
        toFacing(d.x, d.y, d.z);
      } else {
        var d = wrist.sub(pose[a].getPosition());
        reach = d.length() * scale / 3;
        toFacing(d.x, d.y, d.z);
      }
      if (along.length() < 1e-6) return;
      along.normalize();
      var up = new h3d.Vector(1, 0, 0);
      up = up.sub(along.scaled(up.dot(along)));
      if (up.length() < 1e-3) up = new h3d.Vector(0, 0, 1).sub(along.scaled(along.z));
      up.normalize();
      var side = up.cross(along);
      var m = new h3d.Matrix();
      m.identity();
      m._11 = along.x; m._12 = along.y; m._13 = along.z;
      m._21 = side.x; m._22 = side.y; m._23 = side.z;
      m._31 = up.x; m._32 = up.y; m._33 = up.z;
      var euler = m.getEulerAngles();
      found.push({name: name, joint: joint, offset: [round(along.x * reach), round(along.y * reach), round(along.z * reach)],
        rotation: [degrees(euler.x), degrees(euler.y), degrees(euler.z)]});
    }
    hand("sag_el", "RightHand", "RightForeArm");
    hand("sol_el", "LeftHand", "LeftForeArm");
    // Sırt göğsün arkasında, bel sağ kalçada, baş başın kökünde: dönüşsüz, karakterin eksenleriyle.
    // Sağ taraf rigden okunur (sağ kolun düştüğü yan).
    var leftArm = indexOf(joints, "LeftArm"), rightArm = indexOf(joints, "RightArm");
    var right = leftArm < 0 || rightArm < 0 ? -1. : toFacing(pose[rightArm]._41 - pose[leftArm]._41, pose[rightArm]._42 - pose[leftArm]._42, 0).y < 0 ? -1. : 1.;
    var fixed : Array<{name : String, joint : String, offset : Array<Float>}> = [
      {name: "sirt", joint: "Spine", offset: [-0.15, 0, 0]},
      {name: "bel", joint: "Hips", offset: [0, 0.16 * right, 0]},
      {name: "bas", joint: "Head", offset: [0, 0, 0]},
    ];
    for (item in fixed) if (indexOf(joints, item.joint) >= 0) found.push({name: item.name, joint: item.joint, offset: item.offset.copy(), rotation: [0., 0., 0.]});
    return found;
  }

  // Bir kemiğe ağırlığı en az yarım olan köşeler (bağlama pozunda, modelin birimleriyle). Deri bölünmüşse
  // veya köşe biçimi tanınmazsa boş: çağıran kemik çizgisine döner.
  static function boneVertices(hmd : Data, joint : Int) : Array<h3d.Vector> {
    var found = [];
    for (model in hmd.models) {
      if (model.skin == null || model.geometry < 0 || model.skin.split != null || joint >= model.skin.joints.length) continue;
      var bind = model.skin.joints[joint].bind;
      if (bind < 0) continue;
      var geometry = hmd.geometries[model.geometry];
      var format = geometry.vertexFormat;
      var position = format.getInput("position"), weights = format.getInput("weights"), indexes = format.getInput("indexes");
      if (position == null || weights == null || indexes == null || position.precision != F32 || weights.precision != F32 || indexes.type != DBytes4) continue;
      var stride = format.strideBytes, bytes = hmd.data;
      var p = format.calculateInputOffset("position"), w = format.calculateInputOffset("weights"), k = format.calculateInputOffset("indexes");
      var count = weights.type.getSize();
      for (v in 0...geometry.vertexCount) {
        var at = geometry.vertexPosition + v * stride;
        var total = 0., listed = 0.;
        for (c in 0...4) {
          var weight = c < count ? bytes.getFloat(at + w + c * 4) : Math.max(0, 1 - listed);
          if (c < count) listed += weight;
          if (bytes.get(at + k + c) == bind) total += weight;
        }
        if (total >= 0.5) found.push(new h3d.Vector(bytes.getFloat(at + p), bytes.getFloat(at + p + 4), bytes.getFloat(at + p + 8)));
      }
    }
    return found;
  }

  static function palmOf(points : Array<h3d.Vector>, wrist : h3d.Vector) : Null<h3d.Vector> {
    if (points.length == 0) return null;
    var sorted = points.copy();
    sorted.sort((a, b) -> a.distance(wrist) < b.distance(wrist) ? -1 : 1);
    return centroid(sorted.slice(0, Std.int(Math.max(1, sorted.length / 2))));
  }

  static function centroid(points : Array<h3d.Vector>) : Null<h3d.Vector> {
    if (points.length == 0) return null;
    var sum = new h3d.Vector();
    for (point in points) sum = sum.add(point);
    return sum.scaled(1 / points.length);
  }

  static function degrees(radians : Float) : Float {
    var value = Math.round(radians * 1800 / Math.PI) / 10;
    return value == 0 ? 0 : value;
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

  // Meshy her klipte gövdeyi yeniden rigler: kafa ve omuz zincirinin dinlenme pozu klipten klibe değişir.
  // Klibin yerel dönüşleri rige olduğu gibi uygulanınca o kemikler burulur (kafa içine göçer). Burada her
  // eklemin klipteki dinlenme pozuna göre hareketi alınıp rigin dinlenme pozuna uygulanır:
  // rig dünya = rig dinlenme × klip dinlenmesi⁻¹ × klip dünya. Kemik uzunlukları rigden, kalçanın yeri
  // klipten gelir. İki dinlenme pozu aynıysa kareler değişmez. Düzeltilen eklem sayısını döner.
  public static function retarget(anim : h3d.anim.Animation, rig : Data, clip : Data) : Int {
    var linear = Std.downcast(anim, LinearAnimation);
    var rigSkin = skinOf(rig), clipSkin = skinOf(clip);
    if (linear == null || rigSkin == null || clipSkin == null) return 0;
    var rigJoints = rigSkin.joints, clipJoints = clipSkin.joints;
    var clipIndex = [for (i in 0...clipJoints.length) clipJoints[i].name => i];
    var rigIndex = [for (i in 0...rigJoints.length) rigJoints[i].name => i];
    var rigRest = bindPose(rigJoints), clipRest = bindPose(clipJoints);
    var tracks = new Map<String, LinearObject>();
    for (object in @:privateAccess linear.objects) {
      var track = Std.downcast(object, LinearObject);
      if (track != null && track.frames != null) tracks.set(object.objectName, track);
    }
    // Eklem başına sabit düzeltme: rig dinlenme × klip dinlenmesi⁻¹.
    var fix = new Map<Int, h3d.Matrix>();
    var changed = 0;
    for (i in 0...rigJoints.length) {
      var c = clipIndex.get(rigJoints[i].name);
      if (c == null || rigRest[i] == null || clipRest[c] == null) continue;
      var m = new h3d.Matrix();
      m.multiply(rigRest[i], clipRest[c].getInverse());
      fix.set(i, m);
      if (!nearIdentity(m)) changed++;
    }
    if (changed == 0) return 0;
    var rigOrder = depthOrder(rigJoints), clipOrder = depthOrder(clipJoints);
    var clipWorld = [for (_ in clipJoints) new h3d.Matrix()];
    var rigWorld = [for (_ in rigJoints) new h3d.Matrix()];
    var results = new Map<String, Array<LinearFrame>>();
    for (name in tracks.keys()) if (rigIndex.exists(name) && clipIndex.exists(name)) results.set(name, []);
    for (frame in 0...linear.frameCount) {
      for (i in clipOrder) {
        var track = tracks.get(clipJoints[i].name);
        var local = track != null ? track.frames[Std.int(Math.min(frame, track.frames.length - 1))].toMatrix() : clipJoints[i].position.toMatrix();
        if (clipJoints[i].parent < 0) clipWorld[i].load(local) else clipWorld[i].multiply(local, clipWorld[clipJoints[i].parent]);
      }
      for (i in rigOrder) {
        var c = clipIndex.get(rigJoints[i].name);
        var correction = fix.get(i);
        if (c != null && correction != null) rigWorld[i].multiply(correction, clipWorld[c]);
        else {
          var local = rigJoints[i].position.toMatrix();
          if (rigJoints[i].parent < 0) rigWorld[i].load(local) else rigWorld[i].multiply(local, rigWorld[rigJoints[i].parent]);
        }
      }
      for (name => list in results) {
        var i = rigIndex.get(name);
        var parent = rigJoints[i].parent;
        var local = new h3d.Matrix();
        if (parent < 0) local.load(rigWorld[i]) else local.multiply(rigWorld[i], rigWorld[parent].getInverse());
        var out = new LinearFrame();
        var q = new h3d.Quat();
        var unscaled = local.clone();
        unscaled.prependScale(1, 1, 1);
        q.initRotateMatrix(unscaled);
        q.normalize();
        out.qx = q.x;
        out.qy = q.y;
        out.qz = q.z;
        out.qw = q.w;
        out.sx = out.sy = out.sz = 1;
        // Kemik boyu rigin: yalnızca kök (kalça) klibin yerini alır.
        if (parent < 0) {
          out.tx = local._41;
          out.ty = local._42;
          out.tz = local._43;
        } else {
          var rest = new h3d.Matrix();
          rest.multiply(rigRest[i], rigRest[parent].getInverse());
          out.tx = rest._41;
          out.ty = rest._42;
          out.tz = rest._43;
        }
        list.push(out);
      }
    }
    for (name => list in results) {
      var track = tracks.get(name);
      track.frames = haxe.ds.Vector.fromArrayCopy(list);
      track.hasRotation = true;
    }
    return changed;
  }

  // Kollar başka klibin ilk karesinden: köprücükten ele bütün kol eklemleri o duruşta sabit kalır, gövde ve
  // bacaklar hedef klipten oynar. İki klip de önce rige yeniden hedeflenmiş olmalı. Değişen iz sayısı döner.
  public static function holdArms(target : h3d.anim.Animation, pose : h3d.anim.Animation, rig : Data) : Int {
    var skin = skinOf(rig);
    var to = Std.downcast(target, LinearAnimation), from = Std.downcast(pose, LinearAnimation);
    if (skin == null || to == null || from == null) return 0;
    var arms = new Map<String, Bool>();
    for (i in 0...skin.joints.length) {
      var j = i;
      while (j >= 0) {
        var name = skin.joints[j].name;
        if (name == "LeftShoulder" || name == "RightShoulder") {
          arms.set(skin.joints[i].name, true);
          break;
        }
        j = skin.joints[j].parent;
      }
    }
    var sources = new Map<String, LinearObject>();
    for (o in @:privateAccess from.objects) sources.set(o.objectName, cast o);
    var count = 0;
    for (o in @:privateAccess to.objects) {
      if (!arms.exists(o.objectName)) continue;
      var dst : LinearObject = cast o, src = sources.get(o.objectName);
      if (src == null || src.frames == null || src.frames.length == 0 || dst.frames == null) continue;
      var first = src.frames[0];
      dst.frames = haxe.ds.Vector.fromArrayCopy([for (_ in 0...dst.frames.length) {
        var f = new LinearFrame();
        f.tx = first.tx; f.ty = first.ty; f.tz = first.tz;
        f.qx = first.qx; f.qy = first.qy; f.qz = first.qz; f.qw = first.qw;
        f.sx = first.sx; f.sy = first.sy; f.sz = first.sz;
        f;
      }]);
      dst.hasRotation = true;
      count++;
    }
    return count;
  }

  // Dinlenme (bağlama) pozu: bağlama matrisinin tersi. Bağsız eklemde null.
  static function bindPose(joints : Array<SkinJoint>) : Array<Null<h3d.Matrix>> {
    return [for (joint in joints) joint.transpos == null ? null : joint.transpos.toMatrix(true).getInverse()];
  }

  static function nearIdentity(m : h3d.Matrix) : Bool {
    var values = [m._11 - 1, m._12, m._13, m._21, m._22 - 1, m._23, m._31, m._32, m._33 - 1];
    for (v in values) if (Math.abs(v) > 1e-3) return false;
    return Math.abs(m._41) + Math.abs(m._42) + Math.abs(m._43) < 0.05;
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
