package scene.world;

import scene.world.WorldData.TerrainModel;

// Modelin kendi uzayından dünyaya: merkeze taşı, ölçekle, döndür, yerine koy.
class TerrainModels {
  public static function scaleOf(model : TerrainModel) {
    return model.width / model.originWidth;
  }

  public static function place(model : TerrainModel, x : Float, y : Float, z : Float) : Array<Float> {
    var scale = scaleOf(model);
    var angle = model.rotation * Math.PI / 180;
    var localX = (x - model.originX) * scale, localY = (y - model.originY) * scale;
    var cos = Math.cos(angle), sin = Math.sin(angle);
    return [
      model.x + localX * cos - localY * sin,
      model.y + localX * sin + localY * cos,
      model.base + (z - model.originZ) * scale * model.heightScale,
    ];
  }

  // Dikey çarpan yüzey eğimini değiştirir, normal buna göre düzeltilir.
  public static function normal(model : TerrainModel, x : Float, y : Float, z : Float) : Array<Float> {
    var angle = model.rotation * Math.PI / 180;
    var cos = Math.cos(angle), sin = Math.sin(angle);
    var nz = z / model.heightScale;
    var nx = x * cos - y * sin, ny = x * sin + y * cos;
    var length = Math.sqrt(nx * nx + ny * ny + nz * nz);
    return length == 0 ? [0, 0, 1] : [nx / length, ny / length, nz / length];
  }

  public static function copy(models : Array<TerrainModel>) : Array<TerrainModel> {
    return [for (model in models) Reflect.copy(model)];
  }
}
