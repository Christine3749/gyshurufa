#include "HostProtocol.h"

#include <iostream>

int wmain() {
  gy::host::CandidateUiState source{};
  source.caret = RECT{11, 22, 33, 44};
  source.selected = 6;
  source.page_start = 5;
  source.input_mode = 1;
  source.expanded = true;
  source.callback_pipe = L"\\\\.\\pipe\\GYInput.Select.{12345678-1234-1234-1234-123456789abc}";
  source.candidates = {L"你好", L"您好", L"你们"};

  gy::host::CandidateUiState decoded{};
  if (!gy::host::DecodeCandidateUi(gy::host::EncodeCandidateUi(source), &decoded) ||
      decoded.caret.left != source.caret.left || decoded.caret.top != source.caret.top ||
      decoded.caret.right != source.caret.right || decoded.caret.bottom != source.caret.bottom ||
      decoded.selected != source.selected || decoded.page_start != source.page_start ||
      decoded.input_mode != source.input_mode || decoded.expanded != source.expanded || decoded.callback_pipe != source.callback_pipe || decoded.candidates != source.candidates) {
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

  gy::host::HostStatus source_status{L"0.9.39", gy::host::kProtocolVersion, L"0.9.39"};
  gy::host::HostStatus decoded_status{};
  if (!gy::host::DecodeStatus(gy::host::EncodeStatus(source_status), &decoded_status) ||
      decoded_status.host_version != source_status.host_version ||
      decoded_status.protocol_version != source_status.protocol_version ||
      decoded_status.release_version != source_status.release_version) {
    std::wcerr << L"Structured host status round-trip failed.\n";
    return 4;
  }

  gy::host::HostStatus legacy_status{};
  if (!gy::host::DecodeStatus(L"0.9.38", &legacy_status) ||
      legacy_status.host_version != L"0.9.38" || legacy_status.protocol_version != 1) {
    std::wcerr << L"Legacy host status compatibility failed.\n";
    return 5;
  }
  return 0;
}
