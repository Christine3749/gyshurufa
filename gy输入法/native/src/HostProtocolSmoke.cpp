#include "HostProtocol.h"

#include <iostream>

int wmain() {
  const gy::host::LookupRequest lookup_source{L"zhongw", 2, 47};
  gy::host::LookupRequest lookup_decoded{};
  if (!gy::host::DecodeLookupRequest(gy::host::EncodeLookupRequest(lookup_source), &lookup_decoded) ||
      lookup_decoded.text != lookup_source.text || lookup_decoded.input_mode != lookup_source.input_mode ||
      lookup_decoded.mode_generation != lookup_source.mode_generation) {
    std::wcerr << L"Lookup request snapshot round-trip failed.\n";
    return 6;
  }
  const gy::host::LookupResponse response_source{{L"word", L"work"}, 2, 47};
  gy::host::LookupResponse response_decoded{};
  if (!gy::host::DecodeLookupResponse(gy::host::EncodeLookupResponse(response_source), &response_decoded) ||
      response_decoded.candidates != response_source.candidates ||
      !gy::host::MatchesLookupSnapshot(lookup_source, response_decoded)) {
    std::wcerr << L"Lookup response snapshot round-trip failed.\n";
    return 7;
  }
  response_decoded.mode_generation = 46;
  if (gy::host::MatchesLookupSnapshot(lookup_source, response_decoded)) {
    std::wcerr << L"A stale lookup generation was accepted.\n";
    return 8;
  }
  response_decoded = response_source;
  response_decoded.input_mode = 0;
  if (gy::host::MatchesLookupSnapshot(lookup_source, response_decoded)) {
    std::wcerr << L"A cross-mode lookup response was accepted.\n";
    return 9;
  }
  std::wstring malformed_mode = gy::host::EncodeLookupRequest(lookup_source);
  malformed_mode.insert(7, L"x");
  std::wstring malformed_generation = gy::host::EncodeLookupRequest(lookup_source);
  malformed_generation.insert(malformed_generation.find(L'\0', 8), L"x");
  if (gy::host::DecodeLookupRequest(L"zhongw", &lookup_decoded) ||
      gy::host::DecodeLookupRequest(malformed_mode, &lookup_decoded) ||
      gy::host::DecodeLookupRequest(malformed_generation, &lookup_decoded) ||
      gy::host::DecodeLookupResponse(gy::host::EncodeCandidates({L"中文"}), &response_decoded)) {
    std::wcerr << L"A legacy mode-less lookup payload was accepted.\n";
    return 10;
  }

  gy::host::CandidateUiState source{};
  source.caret = RECT{11, 22, 33, 44};
  source.selected = 6;
  source.page_start = 5;
  source.input_mode = 1;
  source.candidate_purpose = 0;
  source.chinese_grid_open = true;
  source.callback_pipe = L"\\\\.\\pipe\\GYInput.Select.{12345678-1234-1234-1234-123456789abc}";
  source.composition = L"nihao";
  source.correction_indices = {1, 2};
  source.candidates = {L"你好", L"您好", L"你们"};

  gy::host::CandidateUiState decoded{};
  if (!gy::host::DecodeCandidateUi(gy::host::EncodeCandidateUi(source), &decoded) ||
      decoded.caret.left != source.caret.left || decoded.caret.top != source.caret.top ||
      decoded.caret.right != source.caret.right || decoded.caret.bottom != source.caret.bottom ||
      decoded.selected != source.selected || decoded.page_start != source.page_start ||
      decoded.input_mode != source.input_mode ||
      decoded.candidate_purpose != source.candidate_purpose ||
      decoded.chinese_grid_open != source.chinese_grid_open ||
      decoded.callback_pipe != source.callback_pipe || decoded.composition != source.composition ||
      decoded.correction_indices != source.correction_indices || decoded.candidates != source.candidates) {
    std::wcerr << L"Candidate UI protocol round-trip failed.\n";
    return 1;
  }

  gy::host::CandidateUiState english_source = source;
  english_source.candidate_purpose = 1;
  english_source.page_start = 25;
  english_source.chinese_grid_open = true;
  english_source.english_list_open = true;
  english_source.english_candidate_focus = true;
  gy::host::CandidateUiState english_decoded{};
  if (!gy::host::DecodeCandidateUi(gy::host::EncodeCandidateUi(english_source), &english_decoded) ||
      english_decoded.candidate_purpose != 1 || english_decoded.page_start != 0 ||
      english_decoded.chinese_grid_open || !english_decoded.english_list_open ||
      !english_decoded.english_candidate_focus) {
    std::wcerr << L"English UI payload lost its list state or retained Chinese paging.\n";
    return 11;
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
      decoded_status.release_version != source_status.release_version ||
      !gy::host::MatchesHostIdentity(decoded_status, L"0.9.39")) {
    std::wcerr << L"Structured host status round-trip failed.\n";
    return 4;
  }

  gy::host::HostStatus wrong_host = decoded_status;
  wrong_host.host_version = L"0.9.38";
  gy::host::HostStatus wrong_release = decoded_status;
  wrong_release.release_version = L"0.9.38";
  gy::host::HostStatus wrong_protocol = decoded_status;
  ++wrong_protocol.protocol_version;
  if (gy::host::MatchesHostIdentity(decoded_status, L"") ||
      gy::host::MatchesHostIdentity(wrong_host, L"0.9.39") ||
      gy::host::MatchesHostIdentity(wrong_release, L"0.9.39") ||
      gy::host::MatchesHostIdentity(wrong_protocol, L"0.9.39")) {
    std::wcerr << L"A missing or mixed-version Host identity was accepted.\n";
    return 12;
  }

  gy::host::HostStatus legacy_status{};
  if (!gy::host::DecodeStatus(L"0.9.38", &legacy_status) ||
      legacy_status.host_version != L"0.9.38" || legacy_status.protocol_version != 1 ||
      gy::host::MatchesHostIdentity(legacy_status, L"0.9.38")) {
    std::wcerr << L"Legacy host status compatibility failed.\n";
    return 5;
  }
  return 0;
}
