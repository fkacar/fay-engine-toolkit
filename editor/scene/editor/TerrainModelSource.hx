package scene.editor;

import scene.world.TerrainSurface.SurfaceGroup;
import sys.FileSystem;
import sys.io.File;

typedef SourceModel = {
  var groups : Array<SurfaceGroup>;  // modelin kendi uzayında, düğüm dönüşümleri uygulanmış
  var minX : Float;
  var maxX : Float;
  var minY : Float;
  var maxY : Float;
  var minZ : Float;
}

// Arazi modelinin kaynakları `assets/terrain/` altındadır. FBX `.editor/terrain/` altında
// çevrilir ve repoya girmez: oyuna hücre parçaları gider. Doku bir kez `res` altına kopyalanır.
class TerrainModelSource {
  public static inline var DIRECTORY = "assets/terrain";

  static inline var CACHE = ".editor/terrain";

  static var cache = new Map<String, {stamp : Float, model : SourceModel}>();

  public static function files() : Array<String> {
    var found = [];
    collect(DIRECTORY, found);
    found.sort(Reflect.compare);
    return found;
  }

  // textures: dokuların kopyalanacağı yer, `res` köküne göre.
  public static function load(importer : AssetImporter, source : String, textures : String, problems : Array<String>) : SourceModel {
    if (!FileSystem.exists(source)) throw 'Arazi kaynağı bulunamadı: $source';
    var stamp = FileSystem.stat(source).mtime.getTime();
    var cached = cache.get(source);
    if (cached != null && cached.stamp == stamp) return cached.model;

    var name = SceneDocument.cleanName(haxe.io.Path.withoutDirectory(haxe.io.Path.withoutExtension(source)));
    var target = '$CACHE/$name/$name.hmd';
    var result = importer.run(source, target);
    for (problem in result.problems) problems.push(problem);
    if (result.target == null) throw '$source içe aktarılamadı';

    var library = hxd.res.Any.fromBytes(target, File.getBytes(target)).toModel().toHmd();
    var root = library.makeObject(_ -> null);
    var model : SourceModel = {groups: [], minX: Math.POSITIVE_INFINITY, maxX: Math.NEGATIVE_INFINITY,
      minY: Math.POSITIVE_INFINITY, maxY: Math.NEGATIVE_INFINITY, minZ: Math.POSITIVE_INFINITY};
    for (mesh in root.getMeshes()) {
      var primitive = Std.downcast(mesh.primitive, h3d.prim.HMDModel);
      if (primitive == null) continue;
      var frame = mesh.getAbsPos();
      var buffers = @:privateAccess primitive.lib.getBuffers(@:privateAccess primitive.data, hxd.BufferFormat.POS3D_NORMAL_UV);
      var vertexes = buffers.vertexes, count = Std.int(vertexes.length / 8);
      var group : SurfaceGroup = {texture: textureOf(library, mesh.material.name, target, textures), positions: [], normals: [], uvs: [], indexes: []};
      var point = new h3d.col.Point(), normal = new h3d.Vector();
      for (i in 0...count) {
        point.set(vertexes[i * 8], vertexes[i * 8 + 1], vertexes[i * 8 + 2]);
        point.transform(frame);
        normal.set(vertexes[i * 8 + 3], vertexes[i * 8 + 4], vertexes[i * 8 + 5]);
        normal.transform3x3(frame);
        normal.normalize();
        group.positions.push(point.x);
        group.positions.push(point.y);
        group.positions.push(point.z);
        group.normals.push(normal.x);
        group.normals.push(normal.y);
        group.normals.push(normal.z);
        group.uvs.push(vertexes[i * 8 + 6]);
        group.uvs.push(vertexes[i * 8 + 7]);
        model.minX = Math.min(model.minX, point.x);
        model.maxX = Math.max(model.maxX, point.x);
        model.minY = Math.min(model.minY, point.y);
        model.maxY = Math.max(model.maxY, point.y);
        model.minZ = Math.min(model.minZ, point.z);
      }
      for (n in 0...buffers.indexes.length) group.indexes.push(buffers.indexes[n]);
      model.groups.push(group);
    }
    cache.set(source, {stamp: stamp, model: model});
    return model;
  }

  static function textureOf(library : hxd.fmt.hmd.Library, material : String, target : String, textures : String) : String {
    for (item in library.header.materials) {
      if (item.name != material || item.diffuseTexture == null) continue;
      var name = haxe.io.Path.withoutDirectory(item.diffuseTexture);
      var from = haxe.io.Path.directory(target) + "/" + name;
      if (!FileSystem.exists(from)) return "";
      var to = 'res/$textures/$name';
      if (!FileSystem.exists('res/$textures')) FileSystem.createDirectory('res/$textures');
      if (!FileSystem.exists(to) || File.getBytes(to).compare(File.getBytes(from)) != 0) File.copy(from, to);
      AssetImporter.forgetMissingFiles();
      return '$textures/$name';
    }
    return "";
  }

  static function collect(directory : String, found : Array<String>) {
    if (!FileSystem.exists(directory)) return;
    for (name in FileSystem.readDirectory(directory)) {
      var path = '$directory/$name';
      if (FileSystem.isDirectory(path)) collect(path, found);
      else if (haxe.io.Path.extension(name).toLowerCase() == "fbx") found.push(path);
    }
  }
}
