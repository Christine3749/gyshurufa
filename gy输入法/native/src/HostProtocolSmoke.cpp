#include "HostProtocol.h"

#include <iostream>

int wmain() {
  gy::host::CandidateUiState source{};
  source.caret = RECT{11, 22, 33, 44};
  source.selected = 6;
  source.page_start = 5;
  source.callback_pipe = L"\\\\.\\pipe\\GYInput.Select.{12345678-1234-1234-1234-123456789abc}";
  source.candidates = {L"你好", L"您好", L"你们"};

  gy::host::CandidateUiState decoded{};
  if (!gy::host::DecodeCandidateUi(gy::host::EncodeCandidateUi(source), &decoded) ||
      decoded.caret.left != source.caret.left || decoded.caret.top != source.caret.top ||
      decoded.caret.right != source.caret.right || decoded.caret.bottom != source.caret.bottom ||
      decoded.selected != source.selected || decoded.page_start != source.page_start ||
      decoded.callback_pipe != source.callback_pipe || decoded.candidates != source.candidates) {
    std::wcerr << L"Candidate UI protocol round-trip failed.\n";
    return 1;
  }

  std::wstring pinyin;
  std::wstring candidate;
  const auto event = gy::host::EncodeLearningEvent(L"nihao", L"你好");
  if (!gy::host::DecodeLearningEvent(event, &pinyin, &candidate) || pinyin != L"nihao" || candidate != L"你好") {
    std::wcerr << L"Learning event protocol round-trip failed.\n";
    return 2;
  }
  if (gy::host::DecodeLearningEvent(L"missing-separator", &pinyin, &candidate)) {
    std::wcerr << L"Malformed learning event was accepted.\n";
    return 3;
  }
  return 0;
}
