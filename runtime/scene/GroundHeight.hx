package scene;

// Oyunun zemini. Verilirse işaretçiler araziye oturur, `z` zeminden yükseklik olur.
interface GroundHeight {
  function heightAt(x : Float, y : Float) : Float;
}
