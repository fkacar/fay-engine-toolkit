package scene.save;

// Oyunda durumu değişen bileşen: tasarlanmış halden farkını verir, geri yükler (docs/KAYIT_PLANI.md).
// saveState farkı yoksa null döner; dönen değer düz JSON verisi olmalı (sayı, metin, dizi, nesne).
// loadState onStart'tan önce çağrılır. Kaydedilen alanlar @:editable değildir, editörde görünmez.
interface Saveable {
  function saveState() : Null<Dynamic>;
  function loadState(state : Dynamic) : Void;
}
