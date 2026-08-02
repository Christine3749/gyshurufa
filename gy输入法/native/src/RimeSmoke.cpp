#include <rime_api.h>

#include <iostream>
#include <string>

int main() {
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = "C:/tmp/gy-rime-runtime/shared";
  traits.user_data_dir = "C:/tmp/gy-rime-runtime/user";
  traits.distribution_name = "GY Input Method";
  traits.distribution_code_name = "gyime";
  traits.distribution_version = "0.1";
  traits.app_name = "rime.gyime.smoke";
  traits.min_log_level = 2;

  RimeApi* rime = rime_get_api();
  rime->setup(&traits);
  rime->initialize(&traits);
  if (rime->start_maintenance(True)) rime->join_maintenance_thread();

  const RimeSessionId session = rime->create_session();
  if (!session) {
    std::cerr << "Unable to create Rime session.\n";
    rime->finalize();
    return 1;
  }
  const Bool selected = rime->select_schema(session, "luna_pinyin");
  std::cout << "select_schema=" << selected << "\n";
  if (!selected) {
    std::cerr << "Unable to select luna_pinyin.\n";
    rime->destroy_session(session);
    rime->finalize();
    return 1;
  }
  rime->set_option(session, "ascii_mode", False);
  const Bool processed = rime->simulate_key_sequence(session, "nihao");
  std::cout << "process_sequence=" << processed << "\n";
  RIME_STRUCT(RimeStatus, status);
  if (rime->get_status(session, &status)) {
    std::cout << "status.schema=" << (status.schema_id ? status.schema_id : "") << " ascii=" << status.is_ascii_mode << " composing=" << status.is_composing << "\n";
    rime->free_status(&status);
  }
  if (!processed) {
    std::cerr << "Unable to process nihao key sequence.\n";
    rime->destroy_session(session);
    rime->finalize();
    return 1;
  }

  RIME_STRUCT(RimeContext, context);
  if (!rime->get_context(session, &context)) {
    std::cerr << "Unable to get Rime context.\n";
    rime->destroy_session(session);
    rime->finalize();
    return 1;
  }
  std::cout << "preedit=" << (context.composition.preedit ? context.composition.preedit : "") << "\n";
  for (int i = 0; i < context.menu.num_candidates && i < 5; ++i) {
    std::cout << "candidate[" << i << "]=" << context.menu.candidates[i].text << "\n";
  }
  rime->free_context(&context);
  rime->destroy_session(session);
  rime->finalize();
  return 0;
}
