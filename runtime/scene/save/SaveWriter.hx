package scene.save;

import scene.save.SaveFile.PackedSection;

// later: iş parçacığında hazırlanacak bölümler (örneğin küçük resmin PNG'si); make yalnızca kendi verisine dokunmalı.
typedef LaterSection = {name : String, make : Void->haxe.io.Bytes};
typedef WriteJob = {path : String, sections : Array<PackedSection>, ?later : Array<LaterSection>, remove : Array<String>, tag : Dynamic};
typedef WriteResult = {job : WriteJob, error : Null<String>, seconds : Float};

// Kayıt dosyalarını arka planda yazar (docs/KAYIT_PLANI.md, Donmasız kayıt): birleştirme, sağlama, geçici dosya,
// doğrulama, yedek ve yerine koyma ayrı bir iş parçacığında; oyun beklemez. İşler sırayla yapılır, iki iş aynı
// dosyaya aynı anda yazmaz. İş parçacığı yalnızca işin baytlarına dokunur. remove: yazmadan önce silinecek
// kayıtlar (yuva dönüşümü, zaman çizgisi), yalnızca .kayit dosyaları ve yedekleri.
class SaveWriter {
  public var threaded(default, null) : Bool;
  public var pending(default, null) = 0;

  var jobs = new sys.thread.Deque<WriteJob>();
  var results = new sys.thread.Deque<WriteResult>();
  var worker : Null<sys.thread.Thread>;

  public function new(threaded = true) {
    this.threaded = threaded;
  }

  public function submit(job : WriteJob) {
    pending++;
    if (!threaded) {
      results.add(run(job));
      return;
    }
    if (worker == null) worker = sys.thread.Thread.create(loop);
    jobs.add(job);
  }

  // Biten işler (ana karede çağrılır, beklemez).
  public function poll() : Array<WriteResult> {
    var done = [];
    while (true) {
      var result = results.pop(false);
      if (result == null) break;
      pending--;
      done.push(result);
    }
    return done;
  }

  // Bekleyen bütün işler bitene kadar bekler: yüklemeden ve çıkıştan önce.
  public function flush() : Array<WriteResult> {
    var done = poll();
    while (pending > 0) {
      done.push(results.pop(true));
      pending--;
    }
    return done;
  }

  function loop() {
    while (true) results.add(run(jobs.pop(true)));
  }

  static function run(job : WriteJob) : WriteResult {
    var begun = haxe.Timer.stamp();
    try {
      for (path in job.remove) {
        if (!StringTools.endsWith(path, "." + SaveSlots.EXTENSION)) continue;
        if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);
        if (sys.FileSystem.exists(path + SaveFile.BACKUP_SUFFIX)) sys.FileSystem.deleteFile(path + SaveFile.BACKUP_SUFFIX);
      }
      var sections = job.sections.copy();
      if (job.later != null) for (section in job.later) sections.push(SaveFile.pack(section.name, section.make()));
      SaveFile.writeSafely(job.path, SaveFile.encodePacked(sections));
      return {job: job, error: null, seconds: haxe.Timer.stamp() - begun};
    } catch (e : Dynamic) {
      return {job: job, error: Std.string(e), seconds: haxe.Timer.stamp() - begun};
    }
  }
}
