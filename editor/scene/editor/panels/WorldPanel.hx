package scene.editor.panels;

import imgui.ImGui;
import scene.editor.HeightmapImport;
import scene.editor.WorldBrush;
import scene.editor.WorldDocument;
import scene.editor.commands.SetEnvironmentCommand;
import scene.world.EnvironmentData;
import scene.world.WorldData;

// Hücre haritası: kuzey üstte, tıklanan hücre yüklenir veya boşaltılır.
class WorldPanel {
  static inline var CELL_SIZE = 24.;
  static inline var FIELD_SHARE = 0.55;
  static inline var LOADED_TIP = "yüklü, boşaltmak için tıkla";
  static inline var UNLOADED_TIP = "yüklü değil, yüklemek için tıkla";
  static inline var DIRTY_TIP = "kaydedilmemiş değişiklik var";

  static var UNLOADED : ImVec4 = {x: 0.25, y: 0.25, z: 0.28, w: 1};
  static var LOADED : ImVec4 = {x: 0.2, y: 0.45, z: 0.7, w: 1};
  static var DIRTY : ImVec4 = {x: 0.85, y: 0.55, z: 0.2, w: 1};

  var editor : Editor;
  var heightmap = "";
  var lowest = 0.;
  var highest = 80.;
  var environmentStart : Null<EnvironmentData>;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    var world = editor.document.world;
    if (world == null) {
      ImGui.textDisabled("Dünya açık değil");
      if (editor.document.canOpenWorld() && ImGui.button("Dünyayı aç")) editor.requestOpen(editor.document.worldPath());
      return;
    }
    drawCells(world);
    if (ImGui.button("Tümünü yükle")) for (cell in world.data.cells()) world.load(cell);
    ImGui.sameLine();
    var bounds = world.showBounds;
    if (ImGui.checkbox("Sınırları göster", bounds)) world.showBounds = bounds;
    ImGui.pushItemWidth(ImGui.getContentRegionAvail().x * FIELD_SHARE);
    if (ImGui.collapsingHeader("Arazi", ImGuiTreeNodeFlags.DefaultOpen)) drawTerrain(world);
    if (ImGui.collapsingHeader("Dağıtma", ImGuiTreeNodeFlags.DefaultOpen)) drawScatter(world);
    if (ImGui.collapsingHeader("Yol ağı")) drawNav(world);
    if (ImGui.collapsingHeader("Ortam")) drawEnvironment(world);
    ImGui.popItemWidth();
  }

  function drawNav(world : WorldDocument) {
    ImGui.textWrapped("Kayıtta değişen hücrelerin yol ağı kendiliğinden yenilenir.");
    if (ImGui.button("Yüklü hücreleri hesapla")) editor.show('Yol ağı güncellendi: ${world.bakeLoaded()} dosya');
    var shown = world.showNav;
    if (ImGui.checkbox("Yürünemeyen yerleri göster", shown)) world.showNav = shown;
  }

  function drawEnvironment(world : WorldDocument) {
    var state = world.state;
    var environment = state.environment;
    var hour = environment.hour, sun = environment.sun, start = environment.fogStart, end = environment.fogEnd;
    if (ImGui.sliderDouble("Saat", hour, 0, 24, "%.1f")) {
      environment.hour = hour;
      state.view.environmentChanged();
    }
    track(world, "Saat");
    if (ImGui.sliderDouble("Güneş", sun, 0, 1.5, "%.2f")) {
      environment.sun = sun;
      state.view.environmentChanged();
    }
    track(world, "Güneş");
    if (ImGui.sliderDouble("Sis başlangıcı", start, 0, 1500, "%.0f")) {
      environment.fogStart = Math.min(start, environment.fogEnd - 1);
      state.view.environmentChanged();
    }
    track(world, "Sis");
    if (ImGui.sliderDouble("Sis bitişi", end, 1, 3000, "%.0f")) {
      environment.fogEnd = Math.max(end, environment.fogStart + 1);
      state.view.environmentChanged();
    }
    track(world, "Sis");
    drawFogColor(world);
    ImGui.textDisabled("Hava durumu");
    for (preset in state.view.weatherPresets()) {
      if (!ImGui.smallButton(preset.title)) continue;
      var before = environment.clone();
      var after = environment.clone();
      after.applyPreset(preset);
      editor.commands.execute(new SetEnvironmentCommand(preset.title, state, before, after, world.environmentEdited));
    }
  }

  function drawFogColor(world : WorldDocument) {
    var environment = world.state.environment;
    var value = environment.fogColor;
    var rgb = new hl.NativeArray<Single>(3);
    rgb[0] = (value >> 16 & 255) / 255;
    rgb[1] = (value >> 8 & 255) / 255;
    rgb[2] = (value & 255) / 255;
    if (ImGui.colorEdit3("Sis rengi", rgb)) {
      environment.fogColor = Math.round(rgb[0] * 255) << 16 | Math.round(rgb[1] * 255) << 8 | Math.round(rgb[2] * 255);
      world.state.view.environmentChanged();
    }
    track(world, "Sis rengi");
  }

  // Sürükleme boyunca değer canlı uygulanır, undo'ya tek adım olarak bırakınca girer.
  function track(world : WorldDocument, label : String) {
    var environment = world.state.environment;
    if (ImGui.isItemActivated()) environmentStart = environment.clone();
    if (!ImGui.isItemDeactivatedAfterEdit() || environmentStart == null) return;
    editor.commands.execute(new SetEnvironmentCommand(label, world.state, environmentStart, environment.clone(), world.environmentEdited));
    environmentStart = null;
  }

  function drawTerrain(world : WorldDocument) {
    var brush = world.brush;
    drawTool(brush, "Seç", null);
    drawTool(brush, "Yükselt", Raise, true);
    drawTool(brush, "Alçalt", Lower, true);
    drawTool(brush, "Düzleştir", Flatten);
    drawTool(brush, "Yumuşat", Smooth, true);
    drawTool(brush, "Boya", Paint, true);
    drawBrushSize(brush);
    if (brush.tool == Paint) {
      var layers = world.data.layers;
      for (index in 0...layers.length) if (ImGui.radioButton(layers[index].title + "##katman", brush.layer == index)) brush.layer = index;
    }
    drawHeightmap(world);
  }

  function drawHeightmap(world : WorldDocument) {
    ImGui.separator();
    var files = HeightmapImport.files();
    if (files.length == 0) {
      ImGui.textDisabled('Yükseklik haritası: ${HeightmapImport.DIRECTORY}/ altına PNG koy');
      return;
    }
    if (ImGui.beginCombo("Yükseklik haritası", heightmap == "" ? "(seç)" : heightmap)) {
      for (name in files) {
        var chosen = name == heightmap;
        if (ImGui.selectable(name, chosen)) heightmap = name;
      }
      ImGui.endCombo();
    }
    var low = lowest, high = highest;
    if (ImGui.inputDouble("En alçak", low)) lowest = low;
    if (ImGui.inputDouble("En yüksek", high)) highest = high;
    ImGui.beginDisabled(heightmap == "");
    if (ImGui.button("Yüklü hücrelere uygula")) applyHeightmap(world);
    ImGui.endDisabled();
  }

  function applyHeightmap(world : WorldDocument) {
    var height = try HeightmapImport.read(heightmap, lowest, highest) catch (e : Dynamic) {
      editor.show('Yükseklik haritası okunamadı: $e', true);
      return;
    }
    var command = world.brush.replaceHeights(height, "Yükseklik haritası");
    if (command != null) editor.commands.execute(command);
  }

  function drawScatter(world : WorldDocument) {
    var brush = world.brush;
    drawTool(brush, "Dağıt", Scatter);
    drawTool(brush, "Sil", Erase, true);
    var types = world.state.view.scatterTypes();
    if (brush.scatterType == "" && brush.tool == Scatter) brush.scatterType = types[0].id;
    for (type in types) if (ImGui.radioButton(type.title + "##tur", brush.scatterType == type.id)) brush.scatterType = type.id;
    if (brush.tool == Erase && ImGui.radioButton("Hepsini sil", brush.scatterType == "")) brush.scatterType = "";
    drawBrushSize(brush);
    var density = brush.density, low = brush.minScale, high = brush.maxScale;
    if (ImGui.sliderDouble("Yoğunluk", density, 0.002, 0.5, "%.3f")) brush.density = density;
    if (ImGui.sliderDouble("En küçük", low, 0.1, 5, "%.2f")) brush.minScale = Math.min(low, brush.maxScale);
    if (ImGui.sliderDouble("En büyük", high, 0.1, 5, "%.2f")) brush.maxScale = Math.max(high, brush.minScale);
  }

  function drawTool(brush : WorldBrush, title : String, tool : Null<BrushTool>, sameLine = false) {
    if (sameLine) ImGui.sameLine();
    if (ImGui.radioButton(title, brush.tool == tool)) brush.tool = tool;
  }

  function drawBrushSize(brush : WorldBrush) {
    var radius = brush.radius, strength = brush.strength;
    if (ImGui.sliderDouble('Yarıçap##${brush.tool}', radius, 1, 120, "%.1f")) brush.radius = radius;
    if (ImGui.sliderDouble('Güç##${brush.tool}', strength, 0.05, 1, "%.2f")) brush.strength = strength;
  }

  function drawCells(world : WorldDocument) {
    var data = world.data;
    var size = CELL_SIZE * editor.interfaceScale;
    var row = data.rows;
    while (row-- > 0) {
      for (column in 0...data.columns) {
        var cell = data.id(column, row);
        if (column > 0) ImGui.sameLine(0, 1);
        drawCell(world, cell, size);
      }
    }
    if (world.isDirty(WorldData.GLOBAL)) ImGui.textDisabled('Genel: $DIRTY_TIP');
    if (world.isEnvironmentDirty()) ImGui.textDisabled('Ortam: $DIRTY_TIP');
  }

  function drawCell(world : WorldDocument, cell : Int, size : Float) {
    var loaded = world.isLoaded(cell), dirty = world.isDirty(cell);
    var color = dirty ? DIRTY : loaded ? LOADED : UNLOADED;
    ImGui.pushStyleColor(ImGuiCol.Button, color);
    ImGui.pushID('$cell');
    var clicked = ImGui.button("##cell", {x: size, y: size});
    ImGui.popID();
    ImGui.popStyleColor();
    if (ImGui.isItemHovered()) ImGui.setTooltip(world.data.title(cell) + ": " + (dirty ? DIRTY_TIP : loaded ? LOADED_TIP : UNLOADED_TIP));
    if (!clicked) return;
    if (!loaded) world.load(cell);
    else editor.guardIf(dirty, () -> world.unload(cell));
  }
}
