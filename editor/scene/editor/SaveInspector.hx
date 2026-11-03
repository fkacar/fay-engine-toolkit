package scene.editor;

// Kayıttan oyna ve kayıt raporu (docs/KAYIT_PLANI.md, Kayıttan oyna). Kayıt biçimi oyunundur: editör listeyi ve
// raporu oyunun verdiği bu arayüzden alır, yalnızca çizer. Satır bir nesneye bağlıysa tıklanınca o nesne seçilir
// (hücresi yüklü değilse yüklenir) ve kamera ona gider; düğmeli satırlar (Eşle) işini oyunun verdiği işlevle yapar.
typedef SaveListing = {path : String, title : String, detail : String};
typedef SaveLine = {text : String, ?entity : String, ?cell : Int, ?action : {label : String, run : Void->Void}};
typedef SaveSection = {title : String, lines : Array<SaveLine>};
typedef SaveInspection = {data : Dynamic, sections : Array<SaveSection>};

interface SaveInspector {
  // Hata ayıklama klasörü: oyuncudan gelen kayıtlar buraya konur, editörden açılan oyunların seferleri de burada.
  var folder(default, null) : String;
  function list() : Array<SaveListing>;
  function inspect(path : String) : SaveInspection;
}
