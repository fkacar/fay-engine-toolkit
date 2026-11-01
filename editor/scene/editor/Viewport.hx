package scene.editor;

import h3d.col.Ray;
import hxd.Key;
import imgui.ImGui;
import imgui.types.ImDrawList;
import scene.Entity;
import scene.editor.Gizmo.GizmoTool;

private enum Mode {
  Idle;
  Pressing;
  BoxSelecting;
  Dragging;
  Flying;
  Orbiting;
  Panning;
  Grabbing;
}

// Panellerin ortasındaki sahne alanı: kamera girdisi, seçim, gizmo ve araç çubuğu.
class Viewport {
  static inline var LEFT = 0;
  static inline var RIGHT = 1;
  static inline var MIDDLE = 2;

  static inline var BOX_THRESHOLD = 8.;
  static inline var BOX_MINIMUM = 16.;
  static inline var TOOLBAR_MARGIN = 6.;
  static inline var FIELD_WIDTH = 56.;
  static inline var SCROLL_ORBIT = 14.;   // iki parmakla döndürme: tekerlek adımında nokta
  static inline var ZOOM_REACH = 4.;      // imleç ufka yakınsa yakınlaşma ekran ortasına düşer
  static inline var GRAB_REACH = 8.;      // ufka yakın ışın çok uzağa düşer, kamera fırlamasın
  static inline var OUTLINE = 0xFFFFB040;
  static inline var BOX_FILL = 0x3040B0FF;
  static inline var BOX_LINE = 0xC040B0FF;

  static inline var CAMERA_TIP = "Tekerlek veya iki parmak: imlece yakınlaş. Option + iki parmak: yatay döndür, dikey eğ. Cmd/Ctrl + iki parmak: döndür. Shift + oklar: döndür, eğ. Sağ tık + WASD: uçuş.";

  static var EDGES = [0, 1, 1, 3, 3, 2, 2, 0, 4, 5, 5, 7, 7, 6, 6, 4, 0, 4, 1, 5, 2, 6, 3, 7];

  public var camera(default, null) : EditorCamera;
  public var gizmo(default, null) : Gizmo;
  public var isFlying(get, never) : Bool;
  public var toolbarBottom(default, null) = 0.;

  var editor : Editor;
  var view : h3d.Camera;
  var mode = Idle;
  var pressX = 0.;
  var pressY = 0.;
  var grabPoint : Null<Vec3>;
  var grabLimit = 0.;
  var sideways = 0.;
  var overlay : WorldOverlay;

  public function new(editor : Editor, view : h3d.Camera) {
    this.editor = editor;
    this.view = view;
    camera = new EditorCamera(view);
    gizmo = new Gizmo(view);
    overlay = new WorldOverlay(view);
  }

  public function update(dt : Float) {
    var density = editor.interfaceScale;
    var mouse = ImGui.getMousePos();
    var ray = view.rayFromScreen(mouse.x, mouse.y);

    readInput(mouse.x, mouse.y, ray, dt);
    recordInput(mouse.x, mouse.y);
    camera.update(dt);
    dropAsset(ray);

    var roots = editor.canEdit() ? editor.selection.roots() : [];
    gizmo.layout(roots, mouse.x, mouse.y, mode == Idle && isHovered(), density);
    var list = ImGui.getBackgroundDrawList();
    overlay.begin(list, camera.forward(), density);
    for (entity in editor.scene.entities) {
      if (!entity.isShown()) continue;
      for (component in entity.components) component.drawOverlay(overlay, editor.selection.has(entity));
    }
    for (entity in editor.selection.items) drawOutline(list, entity, density);
    gizmo.draw(list, density);
    if (mode == BoxSelecting) drawBox(list, mouse.x, mouse.y);
    drawToolbar(density);
  }

  public function centerRay() : Ray {
    var engine = h3d.Engine.getCurrent();
    return view.rayFromScreen(engine.width * 0.5, engine.height * 0.5);
  }

  // Kameranın bozulduğu anı yakalamak için: tasarımcı kaydı dosyaya yazıp sorunla gönderir.
  function recordInput(x : Float, y : Float) {
    var io = ImGui.getIO();
    var keys = (editor.isCommandHeld() ? "cmd " : "") + (Key.isDown(Key.ALT) ? "alt " : "") + (Key.isDown(Key.SHIFT) ? "shift " : "");
    var buttons = (ImGui.isMouseDown(LEFT) ? "sol " : "") + (ImGui.isMouseDown(RIGHT) ? "sag " : "") + (ImGui.isMouseDown(MIDDLE) ? "orta " : "");
    var motion = mode == Idle ? "" : ' dx=${Math.round(io.MouseDelta.x)} dy=${Math.round(io.MouseDelta.y)}';
    var wheel = io.MouseWheel == 0 ? "" : ' tekerlek=${Math.round(io.MouseWheel * 100) / 100}';
    editor.trace.record('$mode tus=[$keys] dugme=[$buttons] panel=${isHovered() ? 0 : 1} mesafe=${Math.round(camera.distance)}$motion$wheel');
  }

  function get_isFlying() {
    return mode == Flying;
  }

  function isHovered() {
    return !ImGui.getIO().WantCaptureMouse;
  }

  // Yalnızca Mac: Heaps yatay kaydırmayı atar, yamalı pencere saklar. macOS'un varsayılanı olan
  // doğal kaydırmada değer parmağın tersi yöndedir, iki parmak sağa gidince sahne sağa dönsün.
  function takeSideways() : Float {
    #if hidpi
    var window = hxd.Window.getInstance();
    var value = -window.horizontalWheel;
    window.horizontalWheel = 0;
    return value;
    #else
    return 0;
    #end
  }

  function readInput(x : Float, y : Float, ray : Ray, dt : Float) {
    sideways = takeSideways();
    var io = ImGui.getIO();
    var dx = io.MouseDelta.x / editor.interfaceScale, dy = io.MouseDelta.y / editor.interfaceScale;
    switch (mode) {
      case Idle:
        if (isHovered()) begin(x, y, ray);
        if (mode == Idle) readKeys(dt);
      case Pressing:
        if (!ImGui.isMouseDown(LEFT)) {
          pickAt(ray);
          mode = Idle;
        } else if (Math.abs(x - pressX) + Math.abs(y - pressY) > BOX_THRESHOLD * editor.interfaceScale) {
          beginDrag(x, y);
        }
      case BoxSelecting:
        if (ImGui.isMouseDown(LEFT)) return;
        // Trackpad'de tıklarken imleç kayar: küçük kutu tıklama sayılır, seçimi boşaltmaz.
        var isClick = Math.max(Math.abs(x - pressX), Math.abs(y - pressY)) < BOX_MINIMUM * editor.interfaceScale;
        if (isClick) pickAt(view.rayFromScreen(pressX, pressY));
        else selectBox(x, y);
        mode = Idle;
      case Dragging:
        gizmo.drag(vectorOf(ray), directionOf(ray), x, editor.interfaceScale);
        if (ImGui.isMouseDown(LEFT)) return;
        var command = gizmo.end();
        if (command != null) editor.commands.execute(command);
        mode = Idle;
      case Flying:
        camera.look(dx, dy);
        camera.fly(dt);
        if (io.MouseWheel != 0) camera.changeSpeed(io.MouseWheel);
        if (!ImGui.isMouseDown(RIGHT)) mode = Idle;
      case Orbiting:
        camera.orbit(dx, dy);
        if (!ImGui.isMouseDown(LEFT)) mode = Idle;
      case Panning:
        camera.pan(io.MouseDelta.x, io.MouseDelta.y, h3d.Engine.getCurrent().height);
        if (!ImGui.isMouseDown(MIDDLE)) mode = Idle;
      case Grabbing:
        grabAt(ray);
        if (!ImGui.isMouseDown(LEFT)) mode = Idle;
    }
  }

  function begin(x : Float, y : Float, ray : Ray) {
    var wheel = ImGui.getIO().MouseWheel;
    if (wheel != 0) readWheel(wheel, ray);
    if (sideways != 0 && (Key.isDown(Key.ALT) || editor.isCommandHeld())) {
      aimAtSurface();
      camera.orbit(sideways * SCROLL_ORBIT, 0);
    }
    if (ImGui.isMouseClicked(RIGHT)) {
      mode = Flying;
    } else if (ImGui.isMouseClicked(MIDDLE)) {
      mode = Panning;
    } else if (ImGui.isMouseClicked(LEFT)) {
      if (gizmo.hovered != 0 && !isRotateHeld()) {
        gizmo.begin(editor.selection.roots(), vectorOf(ray), directionOf(ray), x);
        mode = Dragging;
      } else {
        pressX = x;
        pressY = y;
        var hit = editor.actions.groundHit(ray);
        grabPoint = hit == null ? null : new Vec3(hit.x, hit.y, hit.z);
        grabLimit = hit == null ? 0 : grabPoint.sub(vectorOf(ray)).length() * GRAB_REACH;
        mode = Pressing;
      }
    }
  }

  // Google Maps düzeni: sürükleme kaydırır, Shift (veya Option) ile döndürüp eğer. Yalnızca
  // tıklayıp sürüklemeye dayanır, bu yüzden fare ve trackpad'de aynı çalışır.
  function beginDrag(x : Float, y : Float) {
    if (isRotateHeld()) {
      aimAtSurface();
      camera.orbit((x - pressX) / editor.interfaceScale, (y - pressY) / editor.interfaceScale);
      mode = Orbiting;
    } else if (editor.isCommandHeld()) {
      mode = BoxSelecting;
    } else {
      mode = Grabbing;
    }
  }

  function isRotateHeld() {
    return Key.isDown(Key.SHIFT) || Key.isDown(Key.ALT);
  }

  // Tutulan nokta imlecin altında kalır. Basılan yerde zemin yoksa ekran hareketiyle kayar.
  function grabAt(ray : Ray) {
    if (grabPoint == null) {
      var io = ImGui.getIO();
      camera.pan(io.MouseDelta.x, io.MouseDelta.y, h3d.Engine.getCurrent().height);
      return;
    }
    var hit = GizmoMath.planeHit(vectorOf(ray), directionOf(ray), grabPoint, new Vec3(0, 0, 1));
    if (hit != null && hit.sub(vectorOf(ray)).length() < grabLimit) camera.grab(grabPoint, hit);
  }

  // Option + iki parmak: yatay hareket döndürür, dikey hareket eğer.
  function readWheel(wheel : Float, ray : Ray) {
    if (Key.isDown(Key.ALT)) {
      aimAtSurface();
      camera.orbit(0, -wheel * SCROLL_ORBIT);
      return;
    }
    if (editor.isCommandHeld()) {
      aimAtSurface();
      camera.orbit(wheel * SCROLL_ORBIT, 0);
      return;
    }
    var surface = editor.actions.surfaceDistance(centerRay());
    var hit = editor.actions.groundHit(ray);
    var point = hit == null ? null : new Vec3(hit.x, hit.y, hit.z);
    var isNear = point != null && (surface == null || point.sub(vectorOf(ray)).length() < surface * ZOOM_REACH);
    if (isNear) camera.zoomAt(wheel, point);
    else camera.dolly(wheel, surface);
  }

  // Yazı yazılırken veya kısayol basılıyken klavye kameraya gitmez.
  function readKeys(dt : Float) {
    if (ImGui.getIO().WantCaptureKeyboard || editor.isCommandHeld()) return;
    if (EditorCamera.isTurning()) aimAtSurface();
    camera.drive(dt);
  }

  // Döndürme ekran ortasındaki zemin noktasının etrafında olur.
  function aimAtSurface() {
    var surface = editor.actions.surfaceDistance(centerRay());
    if (surface != null) camera.setDistance(surface);
  }

  function pickAt(ray : Ray) {
    var hit = Picker.pick(editor.scene, ray, editor.actions.visibleDistance(ray));
    var selection = editor.selection;
    if (hit == null) {
      if (!isAdding()) selection.clear();
      return;
    }
    if (isAdding()) selection.toggle(hit);
    else selection.set([hit]);
    editor.hierarchy.reveal(hit);
  }

  // Yalnızca tamamı kutunun içinde kalanlar seçilir: araziye yayılan nesneler her kutuya takılmasın.
  function selectBox(x : Float, y : Float) {
    var left = Math.min(x, pressX), right = Math.max(x, pressX);
    var top = Math.min(y, pressY), bottom = Math.max(y, pressY);
    var picked = isAdding() ? editor.selection.items.copy() : [];
    for (entity in editor.scene.entities) {
      if (!entity.isShown() || picked.indexOf(entity) >= 0) continue;
      var corners = screenCorners(entity);
      if (corners == null) continue;
      if (Lambda.foreach(corners, c -> c.x >= left && c.x <= right && c.y >= top && c.y <= bottom)) picked.push(entity);
    }
    editor.selection.set(picked);
  }

  function isAdding() {
    return Key.isDown(Key.SHIFT) || editor.isCommandHeld();
  }

  // Sürükleme bırakıldığı yerde bir pencere yoksa model sahneye eklenir.
  function dropAsset(ray : Ray) {
    if (editor.assetDrag == null) return;
    if (ImGui.isMouseDown(LEFT)) return;
    var overWindow = ImGui.isWindowHovered(ImGuiHoveredFlags.AnyWindow | ImGuiHoveredFlags.AllowWhenBlockedByActiveItem);
    if (!overWindow) editor.actions.dropAsset(editor.assetDrag, ray);
    editor.assetDrag = null;
  }

  function screenCorners(entity : Entity) : Null<Array<h3d.Vector>> {
    var box = Picker.bounds(entity);
    if (box.isEmpty()) return null;
    var engine = h3d.Engine.getCurrent();
    var eye = new Vec3(view.pos.x, view.pos.y, view.pos.z);
    var ahead = camera.forward();
    var corners = [];
    for (i in 0...8) {
      var x = i & 1 == 0 ? box.xMin : box.xMax, y = i & 2 == 0 ? box.yMin : box.yMax, z = i & 4 == 0 ? box.zMin : box.zMax;
      if (new Vec3(x, y, z).sub(eye).dot(ahead) <= view.zNear) return null;
      corners.push(view.project(x, y, z, engine.width, engine.height));
    }
    return corners;
  }

  function drawOutline(list : ImDrawList, entity : Entity, density : Float) {
    var corners = screenCorners(entity);
    if (corners == null) return;
    var i = 0;
    while (i < EDGES.length) {
      var a = corners[EDGES[i]], b = corners[EDGES[i + 1]];
      list.addLine({x: a.x, y: a.y}, {x: b.x, y: b.y}, OUTLINE, density);
      i += 2;
    }
  }

  function drawBox(list : ImDrawList, x : Float, y : Float) {
    var from : ImVec2 = {x: Math.min(x, pressX), y: Math.min(y, pressY)};
    var to : ImVec2 = {x: Math.max(x, pressX), y: Math.max(y, pressY)};
    list.addRectFilled(from, to, BOX_FILL);
    list.addRect(from, to, BOX_LINE);
  }

  function drawToolbar(density : Float) {
    var margin = TOOLBAR_MARGIN * density;
    ImGui.setNextWindowPos({x: editor.centerX + margin, y: editor.centerY + margin});
    var flags = ImGuiWindowFlags.NoDecoration | ImGuiWindowFlags.AlwaysAutoResize | ImGuiWindowFlags.NoSavedSettings
      | ImGuiWindowFlags.NoFocusOnAppearing | ImGuiWindowFlags.NoDocking | ImGuiWindowFlags.NoNav;
    if (ImGui.begin("##viewport-tools", null, flags)) {
      tool("Taşı (1)", Move);
      tool("Döndür (2)", Rotate);
      tool("Ölçekle (3)", Scale);
      var local = gizmo.localSpace;
      if (ImGui.checkbox("Yerel", local)) gizmo.localSpace = local;

      var snap = gizmo.snapMove, step = gizmo.moveStep;
      if (snapField("Izgara", snap, step, 0.05, density)) {
        gizmo.snapMove = snap;
        gizmo.moveStep = step;
      }
      ImGui.sameLine();
      var snapAngle = gizmo.snapRotate, angle = gizmo.rotateStep;
      if (snapField("Açı", snapAngle, angle, 1, density)) {
        gizmo.snapRotate = snapAngle;
        gizmo.rotateStep = angle;
      }
      ImGui.sameLine();
      var snapSize = gizmo.snapScale, size = gizmo.scaleStep;
      if (snapField("Ölçek", snapSize, size, 0.01, density)) {
        gizmo.snapScale = snapSize;
        gizmo.scaleStep = size;
      }
      ImGui.sameLine();
      if (ImGui.button("Zemine (End)")) editor.actions.snapToGround();
      ImGui.sameLine();
      var items = editor.selection.items;
      ImGui.beginDisabled(items.length < 2);
      if (ImGui.button(editor.groups.isLocked(items) ? "Kilidi aç (L)" : "Kilitle (L)")) editor.toggleLock();
      ImGui.endDisabled();

      ImGui.setNextItemWidth(FIELD_WIDTH * 1.4 * density);
      var speed = camera.speed;
      if (ImGui.dragDouble("Kamera hızı", speed, 0.5, EditorCamera.MIN_SPEED, EditorCamera.MAX_SPEED, "%.1f")) camera.speed = speed;
      ImGui.sameLine();
      ImGui.textDisabled('Sürükle: kaydır, Shift+sürükle: döndür, ${editor.commandName}+sürükle: kutu');
      if (ImGui.isItemHovered()) ImGui.setTooltip(CAMERA_TIP);
      toolbarBottom = ImGui.getWindowPos().y + ImGui.getWindowSize().y;
    }
    ImGui.end();
  }

  function tool(label : String, target : GizmoTool) {
    if (ImGui.radioButton(label, gizmo.tool == target)) gizmo.tool = target;
    ImGui.sameLine();
  }

  function snapField(label : String, enabled : hl.Ref<Bool>, step : hl.Ref<Float>, speed : Float, density : Float) {
    var changed = ImGui.checkbox(label, enabled);
    ImGui.sameLine();
    ImGui.setNextItemWidth(FIELD_WIDTH * density);
    return ImGui.dragDouble('##$label', step, speed, 0.001, 1000, "%.2f") || changed;
  }

  static function vectorOf(ray : Ray) {
    return new Vec3(ray.px, ray.py, ray.pz);
  }

  static function directionOf(ray : Ray) {
    return new Vec3(ray.lx, ray.ly, ray.lz);
  }
}
