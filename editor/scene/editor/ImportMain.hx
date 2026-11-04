package scene.editor;

import sys.FileSystem;

// Komut satırından içe aktarma, pencere açmadan: Asset Browser ve ajanın import_model aracıyla aynı yol
// (AssetImporter.run). Kaynak bir dosya ya da `assets` altında bir klasör olabilir; klasör verilirse içindeki
// modellerin hepsi (alt klasörler dahil) aktarılır. Katalog satırını oyun ekler; bu araç yalnızca dosyaları yazar.
// Mac: ./run.sh ice-aktar <kaynak ...>, Windows: run.bat ice-aktar <kaynak ...>.
class ImportMain {
  static function main() {
    var args = Sys.args();
    if (args.length == 0) {
      Sys.println("Kullanım: ice-aktar <dosya ya da klasör> ...");
      Sys.exit(1);
    }
    var importer = new AssetImporter();
    var known = importer.sources();
    var sources = [];
    for (arg in args) {
      var path = StringTools.replace(arg, "\\", "/");
      while (StringTools.endsWith(path, "/")) path = path.substr(0, path.length - 1);
      if (FileSystem.exists(path) && FileSystem.isDirectory(path)) {
        for (source in known) if (StringTools.startsWith(source, path + "/")) sources.push(source);
      } else sources.push(path);
    }
    var failed = 0;
    for (source in sources) {
      var result = importer.run(source);
      if (result.target == null) {
        failed++;
        Sys.println('HATA $source: ${result.problems.join("; ")}');
        continue;
      }
      var extra = result.notes.concat(result.problems);
      Sys.println('$source -> ${result.target}: ${result.triangles} üçgen${extra.length > 0 ? " (" + extra.join("; ") + ")" : ""}');
    }
    Sys.println('${sources.length - failed}/${sources.length} model içe aktarıldı');
    Sys.exit(failed > 0 ? 1 : 0);
  }
}
