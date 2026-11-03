package scene.save;

import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

// Kayıt dosyasının kabı: adlı bölümler (her biri sıkıştırılmış), sonda sağlama. Oyun bölümlerin içine ne
// koyacağına kendisi karar verir (meta, genel, hücreler...). Dosya platformdan bağımsızdır.
//   "KYT1" | u16 bölüm sayısı | her bölüm: u16 ad uzunluğu, ad, u32 açık boy, u32 sıkışık boy | veriler | u32 CRC32
// Sıkıştırılmış bölüm: hücre bölümleri önbellekte böyle durur, arka plandaki yazıcı yalnızca birleştirir.
typedef PackedSection = {name : String, raw : Int, packed : Bytes};

class SaveFile {
  static inline var MAGIC = "KYT1";
  // Geçici dosya ve yedek .kayit ile bitmez: Steam Cloud yalnızca tam kayıtları görür.
  public static inline var TEMP_SUFFIX = ".yaziliyor";
  public static inline var BACKUP_SUFFIX = ".yedek";

  public static function encode(sections : Array<{name : String, data : Bytes}>) : Bytes {
    return encodePacked([for (section in sections) pack(section.name, section.data)]);
  }

  // Boş bölüm sıkıştırılmaz: HashLink'in zlib'i boş girdide hata verir.
  public static function pack(name : String, data : Bytes) : PackedSection {
    return {name: name, raw: data.length, packed: data.length == 0 ? Bytes.alloc(0) : haxe.zip.Compress.run(data, 6)};
  }

  // Sıkıştırılmış bölümlerden dosya: başlık, veriler, sağlama. Arka planda çalışabilir (yalnızca baytlara dokunur).
  public static function encodePacked(sections : Array<PackedSection>) : Bytes {
    var out = new BytesOutput();
    out.writeString(MAGIC);
    out.writeUInt16(sections.length);
    for (section in sections) {
      var name = Bytes.ofString(section.name);
      out.writeUInt16(name.length);
      out.write(name);
      out.writeInt32(section.raw);
      out.writeInt32(section.packed.length);
    }
    for (section in sections) out.write(section.packed);
    var body = out.getBytes();
    var result = new BytesOutput();
    result.write(body);
    result.writeInt32(haxe.crypto.Crc32.make(body));
    return result.getBytes();
  }

  // Bozuk dosyada hata fırlatır: imza, boylar veya sağlama tutmaz.
  public static function decode(bytes : Bytes) : Map<String, Bytes> {
    if (bytes.length < 10 || bytes.getString(0, 4) != MAGIC) throw "kayıt dosyası değil";
    var body = bytes.sub(0, bytes.length - 4);
    if (haxe.crypto.Crc32.make(body) != bytes.getInt32(bytes.length - 4)) throw "kayıt bozuk (sağlama tutmuyor)";
    var input = new BytesInput(body, 4);
    var count = input.readUInt16();
    var heads = [for (_ in 0...count) {
      var name = input.readString(input.readUInt16());
      {name: name, raw: input.readInt32(), packed: input.readInt32()};
    }];
    var found = new Map<String, Bytes>();
    for (head in heads) {
      var packed = input.read(head.packed);
      var data = head.raw == 0 ? Bytes.alloc(0) : haxe.zip.Uncompress.run(packed, head.raw);
      if (data.length != head.raw) throw 'kayıt bozuk: ${head.name} bölümü eksik';
      found.set(head.name, data);
    }
    return found;
  }

  // Önce geçici dosyaya yazar, geri okuyup doğrular; eski kayıt yedek olur, yenisi yerine geçer.
  // Yazma yarıda kalırsa eski kayıt yerinde durur.
  public static function writeSafely(path : String, bytes : Bytes) {
    var temp = path + TEMP_SUFFIX, backup = path + BACKUP_SUFFIX;
    sys.io.File.saveBytes(temp, bytes);
    decode(sys.io.File.getBytes(temp));
    if (sys.FileSystem.exists(path)) {
      if (sys.FileSystem.exists(backup)) sys.FileSystem.deleteFile(backup);
      sys.FileSystem.rename(path, backup);
    }
    sys.FileSystem.rename(temp, path);
  }

  // Bozuksa yedeği açar. fromBackup oyuncuya söylenir.
  public static function readSafely(path : String) : {sections : Map<String, Bytes>, fromBackup : Bool} {
    try {
      return {sections: decode(sys.io.File.getBytes(path)), fromBackup: false};
    } catch (e : Dynamic) {
      var backup = path + BACKUP_SUFFIX;
      if (!sys.FileSystem.exists(backup)) throw e;
      return {sections: decode(sys.io.File.getBytes(backup)), fromBackup: true};
    }
  }

  public static function json(sections : Map<String, Bytes>, name : String) : Null<Dynamic> {
    var data = sections.get(name);
    return data == null ? null : haxe.Json.parse(data.toString());
  }

  public static function section(name : String, value : Dynamic) : {name : String, data : Bytes} {
    return {name: name, data: Bytes.ofString(haxe.Json.stringify(value))};
  }
}
