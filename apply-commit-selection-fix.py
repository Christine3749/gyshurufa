# -*- coding: utf-8 -*-
"""Pin the caret to the end of committed text (fix reversed insertion in
XAML hosts like Win11 Notepad). Asserted precise edits for GyIme.cpp."""
import pathlib, sys

path = pathlib.Path(r"C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\src\GyIme.cpp")
text = path.read_text(encoding="utf-8")

edits = [
# 1. Signature: CommitComposition needs the context to restore the selection.
(r'''  HRESULT CommitComposition(TfEditCookie cookie, unsigned index, bool raw_text = false) {''',
 r'''  HRESULT CommitComposition(ITfContext* edit_context, TfEditCookie cookie, unsigned index, bool raw_text = false) {'''),
# 2-4. Call sites pass the context through.
(r'''      if (composition_) hr = CommitComposition(cookie, selected_);''',
 r'''      if (composition_) hr = CommitComposition(edit_context, cookie, selected_);'''),
(r'''    if (action.kind == EditActionKind::CommitCandidate) return CommitComposition(cookie, action.index);''',
 r'''    if (action.kind == EditActionKind::CommitCandidate) return CommitComposition(edit_context, cookie, action.index);'''),
(r'''    if (action.kind == EditActionKind::CommitRaw) return CommitComposition(cookie, 0, true);''',
 r'''    if (action.kind == EditActionKind::CommitRaw) return CommitComposition(edit_context, cookie, 0, true);'''),
]

# 5. Keep the range alive past EndComposition (merge two lines to stay unique).
a = r'''      hr = range->SetText(cookie, 0, text.c_str(), static_cast<LONG>(text.size()));'''
b = r'''      range->Release();'''
eol = "\r\n" if (a + "\r\n" + b) in text else "\n"
edits.append((a + eol + b, a))

# 6. After EndComposition, pin the selection to the end of the committed text.
edits.append((
r'''    if (SUCCEEDED(hr)) hr = composition_->EndComposition(cookie);''',
r'''    if (SUCCEEDED(hr)) hr = composition_->EndComposition(cookie);
    // XAML hosts (Win11 Notepad) restore the selection to the composition start
    // on EndComposition; the next commit then inserts before the previous one
    // and text accumulates backwards. Pin the caret to the end of the commit.
    if (SUCCEEDED(hr) && range && edit_context) {
      range->Collapse(cookie, TF_ANCHOR_END);
      TF_SELECTION selection{};
      selection.range = range;
      selection.style.ase = TF_AE_NONE;
      selection.style.fInterimChar = FALSE;
      Trace(L"commit.selection", edit_context->SetSelection(cookie, 1, &selection));
    }
    if (range) range->Release();'''))

for i, (old, new) in enumerate(edits, 1):
    count = text.count(old)
    if count != 1:
        print(f"ABORT: edit #{i} matched {count} times (expected 1)")
        print("anchor:", old[:100])
        sys.exit(1)
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
print(f"OK: {len(edits)} edits applied")
