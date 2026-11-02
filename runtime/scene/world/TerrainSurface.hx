package scene.world;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

typedef SurfaceGroup = {
  var texture : String;           // `res` köküne göre, boşsa dokusuz
  var positions : Array<Float>;   // x, y, z dünya koordinatında
  var normals : Array<Float>;
  var uvs : Array<Float>;         // doku tekrarı uygulanmış
  var indexes : Array<Int>;
}

// Arazi modelinin bir hücreye düşen parçası. İkili dosyadır ve aynı parça her seferinde aynı
// baytları üretir: model yeniden içe aktarılınca değişmeyen hücrenin dosyası yazılmaz.
class TerrainSurface {
  static inline var MAGIC = 0x31465354;  // "TSF1"

  public var groups(default, null) : Array<SurfaceGroup>;

  public function new(?groups : Array<SurfaceGroup>) {
    this.groups = groups == null ? [] : groups;
  }

  public function triangleCount() {
    var count = 0;
    for (group in groups) count += Std.int(group.indexes.length / 3);
    return count;
  }

  public static function read(bytes : Bytes) : TerrainSurface {
    var input = new BytesInput(bytes);
    if (input.readInt32() != MAGIC) throw "Arazi parçası okunamadı";
    var groups = [];
    for (g in 0...input.readInt32()) {
      var texture = input.readString(input.readInt32());
      var vertices = input.readInt32();
      var positions = [for (i in 0...vertices * 3) (input.readFloat() : Float)];
      var normals = [for (i in 0...vertices * 3) (input.readFloat() : Float)];
      var uvs = [for (i in 0...vertices * 2) (input.readFloat() : Float)];
      var indexes = [for (i in 0...input.readInt32()) input.readInt32()];
      groups.push({texture: texture, positions: positions, normals: normals, uvs: uvs, indexes: indexes});
    }
    return new TerrainSurface(groups);
  }

  public function write() : Bytes {
    var output = new BytesOutput();
    output.writeInt32(MAGIC);
    output.writeInt32(groups.length);
    for (group in groups) {
      var name = Bytes.ofString(group.texture);
      output.writeInt32(name.length);
      output.write(name);
      output.writeInt32(Std.int(group.positions.length / 3));
      for (value in group.positions) output.writeFloat(value);
      for (value in group.normals) output.writeFloat(value);
      for (value in group.uvs) output.writeFloat(value);
      output.writeInt32(group.indexes.length);
      for (index in group.indexes) output.writeInt32(index);
    }
    return output.getBytes();
  }
}
