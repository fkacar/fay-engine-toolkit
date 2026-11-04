// Araç takımının hlimgui eklentisine eklediği kare koruması (scene.editor.FrameGuard; derleme tools/build-hlimgui.*).
//
// Haxe kodu bir karenin ortasında hata verirse ImGui'de açık kalan pencere, tablo, ağaç ve yığınlar kapanmaz. Dear
// ImGui bir sonraki NewFrame'de bunu denetler ve uygulamayı durdurur (assert, abort); editör kaydedilmemiş işle
// birlikte kapanır. Buradaki işlevler yarım kalanı kapatır:
//   guard_mark / guard_release / guard_unwind: bir panelin çiziminden önce durum not edilir; hata olursa yalnızca o
//     panelin açtıkları kapanır, editörün geri kalanı aynı karede çizilmeye devam eder.
//   guard_recover_frame: önceki kare yarıda kaldıysa (FrameCountEnded geride) her şey kapatılır ve kare bitirilir.
//   guard_frame_open: kare açık mı (Render ya da EndFrame çağrılmadı); çizimde hata olunca arayüzü yine çizmek için.
// Dear ImGui 1.89'un ErrorCheckEndWindowRecover / ErrorCheckEndFrameRecover işlevlerine dayanır; panel düzeyi aynı
// adımları pencerenin açılışına göre değil, not edilen duruma göre yapar.
#define HL_NAME(n) hlimgui_##n
#include <hl.h>
#include "imgui.h"
#include "imgui_internal.h"

namespace {

struct Mark {
  int windows;
  ImGuiWindow* window;
  ImGuiTable* table;
  ImGuiTabBar* tabBar;
  ImGuiOldColumns* columns;
  int treeDepth, groups, ids, disabled, colors, itemFlags, styleVars, focusScopes, fonts;
};

const int MAX_MARKS = 64;
Mark marks[MAX_MARKS];
int markCount = 0;

}

HL_PRIM int HL_NAME(guard_mark)() {
  ImGuiContext* context = ImGui::GetCurrentContext();
  if (context == NULL || markCount >= MAX_MARKS) return -1;
  ImGuiContext& g = *context;
  ImGuiWindow* window = g.CurrentWindow;
  if (window == NULL) return -1;
  Mark& m = marks[markCount];
  m.windows = g.CurrentWindowStack.Size;
  m.window = window;
  m.table = g.CurrentTable;
  m.tabBar = g.CurrentTabBar;
  m.columns = window->DC.CurrentColumns;
  m.treeDepth = window->DC.TreeDepth;
  m.groups = g.GroupStack.Size;
  m.ids = window->IDStack.Size;
  m.disabled = g.DisabledStackSize;
  m.colors = g.ColorStack.Size;
  m.itemFlags = g.ItemFlagsStack.Size;
  m.styleVars = g.StyleVarStack.Size;
  m.focusScopes = g.FocusScopeStack.Size;
  m.fonts = g.FontStack.Size;
  return markCount++;
}

HL_PRIM void HL_NAME(guard_release)(int index) {
  if (index >= 0 && index <= markCount) markCount = index;
}

HL_PRIM void HL_NAME(guard_unwind)(int index) {
  ImGuiContext* context = ImGui::GetCurrentContext();
  if (context == NULL || index < 0 || index >= markCount) return;
  ImGuiContext& g = *context;
  Mark& m = marks[index];
  // Nottan sonra açılan pencereler (alt pencere, açılır pencere, ipucu) içleriyle birlikte kapanır.
  while (g.CurrentWindowStack.Size > m.windows && g.CurrentWindowStack.Size > 1) {
    ImGui::ErrorCheckEndWindowRecover(NULL);
    ImGuiWindow* window = g.CurrentWindow;
    if (window->Flags & ImGuiWindowFlags_ChildWindow) ImGui::EndChild();
    else ImGui::End();
  }
  ImGuiWindow* window = g.CurrentWindow;
  if (window != m.window) {
    markCount = index;
    return;
  }
  // Not edilen pencerenin içinde: nottan sonra açılanlar, ErrorCheckEndWindowRecover'ın sırasıyla.
  while (g.CurrentTable != NULL && g.CurrentTable != m.table && (g.CurrentTable->OuterWindow == window || g.CurrentTable->InnerWindow == window))
    ImGui::EndTable();
  while (g.CurrentTabBar != NULL && g.CurrentTabBar != m.tabBar) ImGui::EndTabBar();
  if (window->DC.CurrentColumns != NULL && window->DC.CurrentColumns != m.columns) ImGui::EndColumns();
  while (window->DC.TreeDepth > m.treeDepth) ImGui::TreePop();
  while (g.GroupStack.Size > m.groups) ImGui::EndGroup();
  while (window->IDStack.Size > m.ids) ImGui::PopID();
  while (g.DisabledStackSize > m.disabled) ImGui::EndDisabled();
  while (g.ColorStack.Size > m.colors) ImGui::PopStyleColor();
  while (g.ItemFlagsStack.Size > m.itemFlags) ImGui::PopItemFlag();
  while (g.StyleVarStack.Size > m.styleVars) ImGui::PopStyleVar();
  while (g.FocusScopeStack.Size > m.focusScopes) ImGui::PopFocusScope();
  while (g.FontStack.Size > m.fonts) ImGui::PopFont();
  // Sürükle bırak kaynağı ya da hedefi yarıda kaldıysa bayrağı kalır, sonraki BeginDragDrop* denetimi durdurur.
  g.DragDropWithinSource = false;
  g.DragDropWithinTarget = false;
  markCount = index;
}

HL_PRIM bool HL_NAME(guard_recover_frame)() {
  ImGuiContext* context = ImGui::GetCurrentContext();
  markCount = 0;
  if (context == NULL) return false;
  ImGuiContext& g = *context;
  if (g.FrameCount == 0 || g.FrameCountEnded == g.FrameCount) return false;
  g.DragDropWithinSource = false;
  g.DragDropWithinTarget = false;
  ImGui::ErrorCheckEndFrameRecover(NULL);
  ImGui::EndFrame();
  return true;
}

HL_PRIM bool HL_NAME(guard_frame_open)() {
  ImGuiContext* context = ImGui::GetCurrentContext();
  return context != NULL && context->FrameCount > 0 && context->FrameCountEnded != context->FrameCount;
}

DEFINE_PRIM(_I32, guard_mark, _NO_ARG);
DEFINE_PRIM(_VOID, guard_release, _I32);
DEFINE_PRIM(_VOID, guard_unwind, _I32);
DEFINE_PRIM(_BOOL, guard_recover_frame, _NO_ARG);
DEFINE_PRIM(_BOOL, guard_frame_open, _NO_ARG);
