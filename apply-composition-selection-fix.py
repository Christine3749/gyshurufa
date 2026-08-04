# -*- coding: utf-8 -*-
"""Pin the caret to the composition end on every composition update
(XAML hosts leave it at the composition start). Asserted edit."""
import pathlib, sys

path = pathlib.Path(r"C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\src\GyIme.cpp")
text = path.read_text(encoding="utf-8")

old = r'''      if (SUCCEEDED(hr)) ShowCandidates(edit_context, range, cookie);'''
new = r'''      if (SUCCEEDED(hr)) {
        // Measure the candidate anchor on the full composition range first,
        // then pin the caret to the composition end: XAML hosts (Win11
        // Notepad) leave the caret at the composition start after SetText.
        ShowCandidates(edit_context, range, cookie);
        range->Collapse(cookie, TF_ANCHOR_END);
        TF_SELECTION selection{};
        selection.range = range;
        selection.style.ase = TF_AE_NONE;
        selection.style.fInterimChar = FALSE;
        Trace(L"composition.selection", edit_context->SetSelection(cookie, 1, &selection));
      }'''

count = text.count(old)
if count != 1:
    print(f"ABORT: anchor matched {count} times (expected 1)")
    sys.exit(1)
text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
print("OK: 1 edit applied")
