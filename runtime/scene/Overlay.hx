package scene;

// Editörde sahnenin üstüne çizilen yardımcı çizgiler. Renkler 0xAARRGGBB biçimindedir.
interface Overlay {
  function line(x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, color : Int) : Void;
  function label(x : Float, y : Float, z : Float, text : String, color : Int) : Void;
}
