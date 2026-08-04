# -*- coding: utf-8 -*-
"""One-shot precise edits for GyIme.cpp (mixed line endings make Edit-tool
multi-line anchors unreliable). Every replacement asserts exactly 1 hit."""
import pathlib, sys

path = pathlib.Path(r"C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\src\GyIme.cpp")
text = path.read_text(encoding="utf-8")

edits = []

# 1. TraceRect helper (real) inside the GY_IME_TRACE branch.
edits.append((
r'''void Trace(const wchar_t* event, HRESULT hr = S_OK, WPARAM key = 0) {''',
r'''void TraceRect(const wchar_t* event, const RECT& rect) {
  wchar_t directory[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, directory)) return;
  const std::wstring path = std::wstring(directory) + L"GyIme.trace.log";
  const HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  wchar_t line[256]{};
  const int length = swprintf_s(line, L"pid=%lu event=%ls rect=%ld,%ld,%ld,%ld\r\n",
                                GetCurrentProcessId(), event, rect.left, rect.top, rect.right, rect.bottom);
  DWORD written = 0;
  if (length > 0) WriteFile(file, line, static_cast<DWORD>(length * sizeof(wchar_t)), &written, nullptr);
  CloseHandle(file);
}
void Trace(const wchar_t* event, HRESULT hr = S_OK, WPARAM key = 0) {'''))

# 2. TraceRect stub in the #else branch.
edits.append((
r'''void Trace(const wchar_t*, HRESULT = S_OK, WPARAM = 0) {}''',
r'''void Trace(const wchar_t*, HRESULT = S_OK, WPARAM = 0) {}
void TraceRect(const wchar_t*, const RECT&) {}'''))

# 3. Category array before RegisterCategory.
edits.append((
r'''}HRESULT RegisterCategory(bool remove) {''',
r'''}
// A plain TIP_KEYBOARD registration cannot activate in the Windows 11 console
// or Windows Terminal input stack. Register the same capability categories the
// inbox Chinese TIPs carry so the text service is offered there as well.
const GUID kTipCategories[] = {kCategoryTipKeyboard, kCategoryImmersiveSupport, kCategorySystraySupport,
                               kCategoryUiElementEnabled, kCategoryComLess};
HRESULT RegisterCategory(bool remove) {'''))

# 4-5. Register every category in a loop.
edits.append((
r'''  if (remove) hr = categories->UnregisterCategory(CLSID_GyTextService, GUID_TFCAT_TIP_KEYBOARD, CLSID_GyTextService);''',
r'''  for (const GUID& category : kTipCategories) {'''))
edits.append((
r'''  else hr = categories->RegisterCategory(CLSID_GyTextService, GUID_TFCAT_TIP_KEYBOARD, CLSID_GyTextService);''',
r'''    hr = remove ? categories->UnregisterCategory(CLSID_GyTextService, category, CLSID_GyTextService) : categories->RegisterCategory(CLSID_GyTextService, category, CLSID_GyTextService); if (FAILED(hr)) break; }'''))

# 6. Always consult the GUI caret (was: only when no TSF measurement).
edits.append((
r'''    if (!have_caret) {''',
r'''    {  // A clearly disagreeing system caret vetoes the TSF rect: Win11 Notepad's XAML view reports GetTextExt shifted by its tab strip.'''))

# 7. Trace the TSF measurement.
edits.append((
r'''          have_caret = true;''',
r'''          have_caret = true;
          TraceRect(L"caret.tsf", measured);'''))

# 8. GUI caret: veto shifted TSF rects, or serve as fallback (spans 2 lines).
anchor8a = r'''          caret = RECT{origin.x, origin.y, origin.x + (gui.rcCaret.right - gui.rcCaret.left),'''
anchor8b = r'''                       origin.y + (gui.rcCaret.bottom - gui.rcCaret.top)};'''
eol = "\r\n" if (anchor8a + "\r\n" + anchor8b) in text else "\n"
edits.append((
anchor8a + eol + anchor8b,
r'''          const RECT gui_caret{origin.x, origin.y, origin.x + (gui.rcCaret.right - gui.rcCaret.left),
                               origin.y + (gui.rcCaret.bottom - gui.rcCaret.top)};
          const LONG veto = ((caret.bottom - caret.top) > (gui_caret.bottom - gui_caret.top) ? (caret.bottom - caret.top) : (gui_caret.bottom - gui_caret.top)) / 2 + 8;
          if (!have_caret || (caret.top + caret.bottom) - (gui_caret.top + gui_caret.bottom) > 2 * veto || (gui_caret.top + gui_caret.bottom) - (caret.top + caret.bottom) > 2 * veto) { caret = gui_caret; last_caret_ = gui_caret; last_caret_valid_ = true; have_caret = true; TraceRect(L"caret.gui", gui_caret); }'''))

# 10-12. Refresh the now-stale comment inside the GUI block.
edits.append((
r'''      // Never anchor to a caret measured in another context. The key handler''',
r'''      // A caret remembered from another context is never used:'''))
edits.append((
r'''      // runs on the target thread, so that thread's own GUI caret is the best''',
r'''      // last_caret_valid_ keeps cross-context anchors out. The key handler'''))
edits.append((
r'''      // remaining anchor when TSF cannot measure the composition range.''',
r'''      // runs on the target thread, so this thread's GUI caret belongs here.'''))

# 13. Trace the final anchor.
edits.append((
r'''    engine_.ShowCandidates(caret, candidates_, selected_, page_start_, input_mode_, expanded_candidates_, selection_callback_.Endpoint());''',
r'''    TraceRect(L"caret.pick", caret);
    engine_.ShowCandidates(caret, candidates_, selected_, page_start_, input_mode_, expanded_candidates_, selection_callback_.Endpoint());'''))

for i, (old, new) in enumerate(edits, 1):
    count = text.count(old)
    if count != 1:
        print(f"ABORT: edit #{i} matched {count} times (expected 1)")
        print("anchor:", old[:100])
        sys.exit(1)
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
print(f"OK: {len(edits)} edits applied")
