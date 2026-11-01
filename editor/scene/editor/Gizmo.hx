package scene.editor;

import h3d.Matrix;
import h3d.Vector;
import imgui.ImGui;
import imgui.types.ImDrawList;
import scene.Entity;
import scene.editor.commands.GroupCommand;
import scene.editor.commands.SetTransformCommand;
import scene.editor.commands.SetTransformCommand.Transform;

enum GizmoTool {
  Move;
  Rotate;
  Scale;
}

private typedef Grip = {
  var entity : Entity;
  var start : Transform;
  var world : Vec3;
  var rotation : Matrix;
  var toParent : Matrix;
  var toParentRotation : Matrix;
}

private typedef Stroke = {
  var handle : Int;
  var ax : Float;
  var ay : Float;
  var bx : Float;
  var by : Float;
}

private typedef Patch = {
  var handle : Int;
  var points : Array<Vector>;
}

// ImGuizmo binding'i yok, tutamaçlar ImGui çizim listesine elle çizilir. Hesaplar dünya
// uzayındadır, sonuç nesnenin üst nesnesine göre yerel değerlere çevrilir.
class Gizmo {
  static inline var X = 1;
  static inline var Y = 2;
  static inline var Z = 4;
  static inline var XY = 3;
  static inline var XZ = 5;
  static inline var YZ = 6;
  static inline var ALL = 7;

  static inline var SIZE = 95;           // nokta
  static inline var THICKNESS = 2.5;
  static inline var HOVER_RANGE = 8.;
  static inline var ARROW = 0.14;        // eksen boyunun katı
  static inline var PLANE_START = 0.22;
  static inline var PLANE_END = 0.5;
  static inline var CENTER = 5.;
  static inline var CIRCLE_STEPS = 56;
  static inline var HIDDEN_AXIS = 0.985;
  static inline var UNIFORM_RANGE = 150.;
  static inline var MIN_SCALE = 0.001;

  static inline var RED = 0xFFE64A4A;
  static inline var GREEN = 0xFF4AD24A;
  static inline var BLUE = 0xFF3A8AF0;
  static inline var WHITE = 0xFFE0E0E0;
  static inline var ACTIVE = 0xFFF4D830;
  static inline var PATCH_ALPHA = 0x70FFFFFF;

  public var tool = Move;
  public var localSpace = false;
  public var snapMove = false;
  public var moveStep = 1.;
  public var snapRotate = false;
  public var rotateStep = 15.;
  public var snapScale = false;
  public var scaleStep = 0.1;
  public var hovered(default, null) = 0;
  public var isDragging(get, never) : Bool;

  var camera : h3d.Camera;
  var pivot : Null<Vec3>;
  var axes : Array<Vec3> = [];
  var length = 1.;
  var strokes : Array<Stroke> = [];
  var patches : Array<Patch> = [];

  var handle = 0;
  var grips : Array<Grip> = [];
  var startPivot : Vec3;
  var startAxes : Array<Vec3>;
  var startParam = 0.;
  var startPoint : Vec3;
  var startMouseX = 0.;

  public function new(camera : h3d.Camera) {
    this.camera = camera;
  }

  // Her karede tutamaçların ekran konumlarını çıkarır, fare altındakini bulur.
  public function layout(entities : Array<Entity>, mouseX : Float, mouseY : Float, canHover : Bool, density : Float) {
    strokes = [];
    patches = [];
    hovered = 0;
    pivot = null;
    if (entities.length == 0) return;

    var center = centerOf(entities);
    var eye = vec(camera.pos);
    var view = vec(camera.target).sub(eye).normalized();
    var depth = center.sub(eye).dot(view);
    if (depth <= camera.zNear) return;

    pivot = center;
    axes = isDragging ? startAxes : axesOf(entities[entities.length - 1]);
    var height = h3d.Engine.getCurrent().height;
    length = SIZE * density * 2 * depth * Math.tan(camera.fovY * Math.PI / 360) / height;

    switch (tool) {
      case Move: layoutMove(view, density);
      case Rotate: layoutRotate(eye);
      case Scale: layoutScale(view, density);
    }
    if (canHover && !isDragging) hovered = find(mouseX, mouseY, density);
  }

  public function begin(entities : Array<Entity>, rayPos : Vec3, rayDir : Vec3, mouseX : Float) {
    handle = hovered;
    grips = [for (entity in entities) grip(entity)];
    startPivot = pivot;
    startAxes = axes;
    startMouseX = mouseX;
    var single = axisIndex(handle);
    switch (tool) {
      case Move if (single >= 0):
        startParam = GizmoMath.axisParam(rayPos, rayDir, startPivot, axes[single]);
      case Move:
        startPoint = GizmoMath.planeHit(rayPos, rayDir, startPivot, axes[planeNormal(handle)]);
      case Rotate:
        var hit = GizmoMath.planeHit(rayPos, rayDir, startPivot, axes[single]);
        startPoint = hit == null ? null : hit.sub(startPivot);
      case Scale if (handle != ALL):
        startParam = GizmoMath.axisParam(rayPos, rayDir, startPivot, axes[single]);
      case Scale:
    }
  }

  public function drag(rayPos : Vec3, rayDir : Vec3, mouseX : Float, density : Float) {
    switch (tool) {
      case Move: dragMove(rayPos, rayDir);
      case Rotate: dragRotate(rayPos, rayDir);
      case Scale: dragScale(rayPos, rayDir, mouseX, density);
    }
  }

  public function end() : Null<Command> {
    var changed : Array<Command> = [];
    for (grip in grips) {
      var after = SetTransformCommand.capture(grip.entity);
      if (!SetTransformCommand.same(grip.start, after)) changed.push(new SetTransformCommand(grip.entity, grip.start, after));
    }
    handle = 0;
    grips = [];
    if (changed.length == 0) return null;
    var label = switch (tool) {
      case Move: "Taşı";
      case Rotate: "Döndür";
      case Scale: "Ölçekle";
    };
    return new GroupCommand(label, changed);
  }

  public function draw(list : ImDrawList, density : Float) {
    if (pivot == null) return;
    var thickness = THICKNESS * density;
    for (stroke in strokes) list.addLine({x: stroke.ax, y: stroke.ay}, {x: stroke.bx, y: stroke.by}, colorOf(stroke.handle), thickness);
    for (patch in patches) {
      var p = patch.points;
      var color = colorOf(patch.handle) & PATCH_ALPHA | (isSingle(patch.handle) ? 0xFF000000 : 0);
      if (p.length == 3) list.addTriangleFilled({x: p[0].x, y: p[0].y}, {x: p[1].x, y: p[1].y}, {x: p[2].x, y: p[2].y}, colorOf(patch.handle));
      else list.addQuadFilled({x: p[0].x, y: p[0].y}, {x: p[1].x, y: p[1].y}, {x: p[2].x, y: p[2].y}, {x: p[3].x, y: p[3].y}, color);
    }
  }

  // Dünya konumunu seçili nesnelerin ortasına çevirir: odaklama da bunu kullanır.
  public static function centerOf(entities : Array<Entity>) {
    var sum = new Vec3();
    for (entity in entities) sum = sum.add(worldPosition(entity));
    return sum.scale(1 / entities.length);
  }

  public static function worldPosition(entity : Entity) {
    var at = entity.object.getAbsPos().getPosition();
    return new Vec3(at.x, at.y, at.z);
  }

  // Heaps satır vektörü kullanır: a.multiply(a, b) önce a'yı, sonra b'yi uygular.
  public static function worldRotation(object : h3d.scene.Object) {
    var result = new Matrix();
    result.identity();
    var step = new Matrix();
    var current = object;
    while (current != null) {
      current.getRotationQuat().toMatrix(step);
      result.multiply3x4(result, step);
      current = current.parent;
    }
    return result;
  }

  function get_isDragging() {
    return handle != 0;
  }

  function axesOf(entity : Entity) {
    if (!localSpace && tool != Scale) return [new Vec3(1, 0, 0), new Vec3(0, 1, 0), new Vec3(0, 0, 1)];
    var m = worldRotation(entity.object);
    return [new Vec3(m._11, m._12, m._13), new Vec3(m._21, m._22, m._23), new Vec3(m._31, m._32, m._33)];
  }

  function grip(entity : Entity) : Grip {
    var parent = entity.object.parent;
    var toParentRotation = worldRotation(parent);
    toParentRotation.transpose();
    return {
      entity: entity,
      start: SetTransformCommand.capture(entity),
      world: worldPosition(entity),
      rotation: worldRotation(entity.object),
      toParent: parent.getInvPos().clone(),
      toParentRotation: toParentRotation,
    };
  }

  function moveGrip(grip : Grip, world : Vec3) {
    var delta = world.sub(grip.world);
    var local = new Vector(delta.x, delta.y, delta.z);
    local.transform3x3(grip.toParent);
    var start = grip.start.position;
    grip.entity.setPosition(start[0] + local.x, start[1] + local.y, start[2] + local.z);
  }

  function dragMove(rayPos : Vec3, rayDir : Vec3) {
    var delta = new Vec3();
    var single = axisIndex(handle);
    if (single >= 0) {
      var param = GizmoMath.axisParam(rayPos, rayDir, startPivot, startAxes[single]);
      if (param == null) return;
      delta = startAxes[single].scale(param - startParam);
    } else {
      var hit = GizmoMath.planeHit(rayPos, rayDir, startPivot, startAxes[planeNormal(handle)]);
      if (hit == null || startPoint == null) return;
      delta = hit.sub(startPoint);
    }
    if (snapMove) delta = snapDelta(delta);
    for (grip in grips) moveGrip(grip, grip.world.add(delta));
  }

  // Dünya eksenlerinde izgaraya, yerel eksenlerde adım katlarına oturur.
  function snapDelta(delta : Vec3) {
    var snapped = new Vec3();
    for (i in 0...3) {
      if (handle & (1 << i) == 0) continue;
      var axis = startAxes[i];
      var start = startPivot.dot(axis);
      snapped = snapped.add(axis.scale(GizmoMath.snap(start + delta.dot(axis), moveStep) - start));
    }
    return snapped;
  }

  function dragRotate(rayPos : Vec3, rayDir : Vec3) {
    var normal = startAxes[axisIndex(handle)];
    var hit = GizmoMath.planeHit(rayPos, rayDir, startPivot, normal);
    if (hit == null || startPoint == null) return;
    var angle = GizmoMath.signedAngle(startPoint, hit.sub(startPivot), normal);
    if (snapRotate) angle = GizmoMath.snap(angle * 180 / Math.PI, rotateStep) * Math.PI / 180;

    var turn = new Matrix();
    turn.initRotationAxis(new Vector(normal.x, normal.y, normal.z), angle);
    for (grip in grips) {
      var offset = grip.world.sub(startPivot);
      var turned = new Vector(offset.x, offset.y, offset.z);
      turned.transform3x3(turn);
      moveGrip(grip, startPivot.add(vec(turned)));

      var world = new Matrix();
      world.multiply3x4(grip.rotation, turn);
      var local = new Matrix();
      local.multiply3x4(world, grip.toParentRotation);
      var euler = local.getEulerAngles();
      grip.entity.setRotation(euler.x * 180 / Math.PI, euler.y * 180 / Math.PI, euler.z * 180 / Math.PI);
    }
  }

  function dragScale(rayPos : Vec3, rayDir : Vec3, mouseX : Float, density : Float) {
    var single = axisIndex(handle);
    var factor = 1 + (mouseX - startMouseX) / (UNIFORM_RANGE * density);
    if (handle != ALL) {
      var param = GizmoMath.axisParam(rayPos, rayDir, startPivot, startAxes[single]);
      if (param == null || startParam == 0) return;
      factor = param / startParam;
    }
    factor = Math.max(factor, MIN_SCALE);
    for (grip in grips) {
      var scale = grip.start.scale;
      var next = [for (i in 0...3) handle & (1 << i) == 0 ? scale[i] : scaled(scale[i], factor)];
      grip.entity.setScale(next[0], next[1], next[2]);

      var offset = grip.world.sub(startPivot);
      if (handle == ALL) offset = offset.scale(factor);
      else offset = offset.add(startAxes[single].scale(offset.dot(startAxes[single]) * (factor - 1)));
      moveGrip(grip, startPivot.add(offset));
    }
  }

  function scaled(value : Float, factor : Float) {
    var result = value * factor;
    if (snapScale) result = GizmoMath.snap(result, scaleStep);
    return Math.abs(result) < MIN_SCALE ? MIN_SCALE : result;
  }

  function layoutMove(view : Vec3, density : Float) {
    for (i in 0...3) {
      var axis = axes[i];
      if (Math.abs(axis.dot(view)) > HIDDEN_AXIS) continue;
      var tip = pivot.add(axis.scale(length));
      addStroke(1 << i, pivot, tip);
      addArrow(1 << i, tip, axis, view);
    }
    addPlane(XY, 0, 1, view);
    addPlane(XZ, 0, 2, view);
    addPlane(YZ, 1, 2, view);
  }

  function layoutRotate(eye : Vec3) {
    var toEye = eye.sub(pivot).normalized();
    for (i in 0...3) {
      var u = axes[(i + 1) % 3], v = axes[(i + 2) % 3];
      var previous = null;
      for (step in 0...CIRCLE_STEPS + 1) {
        var angle = step * Math.PI * 2 / CIRCLE_STEPS;
        var out = u.scale(Math.cos(angle)).add(v.scale(Math.sin(angle)));
        var point = pivot.add(out.scale(length));
        // Arka yarı çizilmez: üst üste binen halkalar okunmaz olur.
        var facing = out.dot(toEye) > -0.05;
        if (previous != null && facing) addStroke(1 << i, previous, point);
        previous = facing ? point : null;
      }
    }
  }

  function layoutScale(view : Vec3, density : Float) {
    for (i in 0...3) {
      var axis = axes[i];
      if (Math.abs(axis.dot(view)) > HIDDEN_AXIS) continue;
      var tip = pivot.add(axis.scale(length));
      addStroke(1 << i, pivot, tip);
      addBox(1 << i, tip, CENTER * density);
    }
    addBox(ALL, pivot, CENTER * 1.4 * density);
  }

  function addStroke(handle : Int, from : Vec3, to : Vec3) {
    var a = project(from), b = project(to);
    strokes.push({handle: handle, ax: a.x, ay: a.y, bx: b.x, by: b.y});
  }

  function addArrow(handle : Int, tip : Vec3, axis : Vec3, view : Vec3) {
    var side = axis.cross(view).normalized().scale(length * ARROW * 0.4);
    var base = tip.sub(axis.scale(length * ARROW));
    patches.push({handle: handle, points: [project(tip.add(axis.scale(length * ARROW))), project(base.add(side)), project(base.sub(side))]});
  }

  function addPlane(handle : Int, a : Int, b : Int, view : Vec3) {
    var u = axes[a].scale(length), v = axes[b].scale(length);
    if (Math.abs(u.cross(v).normalized().dot(view)) < 1 - HIDDEN_AXIS) return;
    var corner = pivot.add(u.scale(PLANE_START)).add(v.scale(PLANE_START));
    var size = PLANE_END - PLANE_START;
    patches.push({handle: handle, points: [
      project(corner),
      project(corner.add(u.scale(size))),
      project(corner.add(u.scale(size)).add(v.scale(size))),
      project(corner.add(v.scale(size))),
    ]});
  }

  function addBox(handle : Int, at : Vec3, half : Float) {
    var c = project(at);
    patches.push({handle: handle, points: [
      new Vector(c.x - half, c.y - half),
      new Vector(c.x + half, c.y - half),
      new Vector(c.x + half, c.y + half),
      new Vector(c.x - half, c.y + half),
    ]});
  }

  function project(point : Vec3) : Vector {
    var engine = h3d.Engine.getCurrent();
    return camera.project(point.x, point.y, point.z, engine.width, engine.height);
  }

  // Yüzeyler kalın çizgilerden öncedir: küçük kareler aksi halde hiç yakalanmaz.
  function find(mouseX : Float, mouseY : Float, density : Float) {
    for (patch in patches) if (inside(patch.points, mouseX, mouseY)) return patch.handle;
    var nearest = 0, best = HOVER_RANGE * density;
    for (stroke in strokes) {
      var distance = GizmoMath.segmentDistance(mouseX, mouseY, stroke.ax, stroke.ay, stroke.bx, stroke.by);
      if (distance >= best) continue;
      best = distance;
      nearest = stroke.handle;
    }
    return nearest;
  }

  // Dışbükey çokgen: nokta her kenarın aynı tarafında olmalı.
  function inside(points : Array<Vector>, x : Float, y : Float) {
    var side = 0;
    for (i in 0...points.length) {
      var a = points[i], b = points[(i + 1) % points.length];
      var cross = (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x);
      var sign = cross > 0 ? 1 : -1;
      if (side != 0 && sign != side) return false;
      side = sign;
    }
    return true;
  }

  function colorOf(handle : Int) {
    if (handle == hovered || handle == this.handle) return ACTIVE;
    return switch (handle) {
      case X, YZ: RED;
      case Y, XZ: GREEN;
      case Z, XY: BLUE;
      default: WHITE;
    };
  }

  static function isSingle(handle : Int) {
    return handle == X || handle == Y || handle == Z || handle == ALL;
  }

  static function axisIndex(handle : Int) {
    return switch (handle) {
      case X: 0;
      case Y: 1;
      case Z: 2;
      default: -1;
    };
  }

  static function planeNormal(handle : Int) {
    return switch (handle) {
      case YZ: 0;
      case XZ: 1;
      default: 2;
    };
  }

  static function vec(v : Vector) {
    return new Vec3(v.x, v.y, v.z);
  }
}
