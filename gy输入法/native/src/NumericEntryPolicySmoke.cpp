#include "NumericEntryPolicy.h"

int main() {
  using gy::numeric_entry::CharacterFor;
  if (!gy::numeric_entry::StartsFragment(L'9', false) ||
      CharacterFor(L'9', false, false) != L'9' ||
      CharacterFor(VK_OEM_PERIOD, false, true) != L'.' ||
      CharacterFor(VK_OEM_MINUS, false, true) != L'-' ||
      CharacterFor(VK_OEM_1, true, true) != L':' ||
      CharacterFor(VK_OEM_2, false, true) != L'/' ||
      CharacterFor(L'5', true, true) != L'%' ||
      CharacterFor(VK_OEM_PERIOD, false, false) != 0 ||
      CharacterFor(L'5', true, false) != 0) return 1;
  return 0;
}
