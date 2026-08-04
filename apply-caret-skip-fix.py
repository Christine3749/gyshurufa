# -*- coding: utf-8 -*-
"""Never anchor the candidate window to a rect that was never measured in the
current context (the Kimi drift: Chromium layout race right after an app
switch made GetTextExt fail, and the code showed at a stale rect)."""
import pathlib, sys

path = pathlib.Path(r"C:\Users\Ethan\Desktop\01-Projects\shurufa\gy输入法\native\src\GyIme.cpp")
text = path.read_text(encoding="utf-8")

old = r'''    TraceRect(L"caret.pick", caret);'''
new = r'''    if (!have_caret && !last_caret_valid_) {
      // Nothing was ever measured in this context (Chromium's layout can lag
      // one keystroke right after an app switch). One late frame is harmless;
      // a window shown at a stale rect is the drift users actually see.
      TraceRect(L"caret.skip", caret);
      return;
    }
    TraceRect(L"caret.pick", caret);'''

count = text.count(old)
if count != 1:
    print(f"ABORT: anchor matched {count} times (expected 1)")
    sys.exit(1)
text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
print("OK: 1 edit applied")
