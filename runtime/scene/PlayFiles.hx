package scene;

// Editör ile onun açtığı oyun süreci arasındaki dosyalar. Soket yerine dosya: iki platformda da aynı
// çalışır, oyun çökerse editör etkilenmez. Hepsi kişiye özel `bin/` altındadır, git'e girmez.
class PlayFiles {
  public static inline var DIRECTORY = "bin/ajan";
  public static inline var STATE = DIRECTORY + "/oyun-durumu.json";   // oyun saniyede dört kez yazar
  public static inline var TRACE = DIRECTORY + "/oyun-izi.jsonl";     // olay izi, satır başına bir kayıt
  public static inline var SCRIPT = DIRECTORY + "/senaryo.json";      // görev testi: editör yazar, oyun okur
  public static inline var RESULT = DIRECTORY + "/sonuc.json";        // görev testinin sonucu
  public static inline var TESTS = "res/tests";                       // tasarımcının görev testleri
  public static inline var TEST_SUFFIX = ".test.json";
}
