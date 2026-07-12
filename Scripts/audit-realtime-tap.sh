#!/bin/bash
set -euo pipefail

fail() {
  echo "$*" >&2
  exit 1
}

line_count() {
  awk 'NF { count += 1 } END { print count + 0 }' <<< "$1"
}

list_contains() {
  local needle="$1"
  local values="$2"
  local value

  for value in $values; do
    if test "$value" = "$needle"; then
      return 0
    fi
  done
  return 1
}

audit_noise_symbols() {
  local symbols="$1"

  if rg -q 'AVAudioPCMBuffer.*Ieggg_AbDIeyByy_TR' <<< "$symbols"; then
    fail 'Swift AVAudioPCMBuffer tap thunk is still present'
  fi
}

classify_branch_target() {
  local label="$1"
  local target="$2"

  if rg -q \
    '(swift|objc)_[[:alnum:]_]*(retain|release|Retain|Release)|objc_storeStrong|_Block_object_(assign|dispose)' \
    <<< "$target"; then
    fail "forbidden ownership traffic in $label: $target"
  fi
  if rg -q \
    '(^|_)(malloc|calloc|realloc|free|valloc|aligned_alloc)($|_)|(^|_)(swift|objc)_[[:alnum:]_]*(alloc|Alloc|dealloc|Dealloc)' \
    <<< "$target"; then
    fail "forbidden allocation/free traffic in $label: $target"
  fi
  if rg -q \
    'os_unfair_lock|pthread_(mutex|rwlock|spin)|dispatch_semaphore|semaphore_(wait|signal)|objc_sync_(enter|exit)' \
    <<< "$target"; then
    fail "forbidden lock/semaphore traffic in $label: $target"
  fi
  if rg -q \
    '(^|_)dispatch_|(^|_)swift_task|swift_continuation|Continuation|pthread_cond|mach_msg|kevent|kqueue|nanosleep|usleep|(^|_)sleep($|_)|(^|_)wait($|_)|wake|Wake' \
    <<< "$target"; then
    fail "forbidden dispatch/task/wakeup/blocking traffic in $label: $target"
  fi
}

audit_target_list() {
  local label="$1"
  local targets="$2"
  local allowed="$3"
  local required="$4"
  local target

  for target in $targets; do
    classify_branch_target "$label" "$target"
    if ! list_contains "$target" "$allowed"; then
      fail "unexpected branch target in $label: $target"
    fi
  done

  for target in $required; do
    if ! list_contains "$target" "$targets"; then
      fail "expected branch target missing from $label: $target"
    fi
  done
}

run_fixture() {
  local fixture="$1"
  local target
  local disassembly

  case "$fixture" in
    old-swift-thunk)
      audit_noise_symbols \
        '0000 (__TEXT,__text) _$sSo16AVAudioPCMBufferCSo0A4TimeCIeggg_AbDIeyByy_TR'
      ;;
    bridge-ownership)
      target='_swift_retain'
      disassembly="$(fixture_disassembly "$target")"
      audit_disassembly \
        'fixture bridge callback' \
        "$disassembly" \
        "$target" \
        "$target" \
        0
      ;;
    submit-allocation)
      target='_malloc'
      disassembly="$(fixture_disassembly "$target")"
      audit_disassembly \
        'fixture SpectrumMailbox.submit' \
        "$disassembly" \
        "$target" \
        "$target" \
        0
      ;;
    submit-lock)
      target='_pthread_mutex_lock'
      disassembly="$(fixture_disassembly "$target")"
      audit_disassembly \
        'fixture SpectrumMailbox.submit' \
        "$disassembly" \
        "$target" \
        "$target" \
        0
      ;;
    submit-dispatch)
      target='_dispatch_async'
      disassembly="$(fixture_disassembly "$target")"
      audit_disassembly \
        'fixture SpectrumMailbox.submit' \
        "$disassembly" \
        "$target" \
        "$target" \
        0
      ;;
    submit-unexpected-call)
      target='_audio_unexpected_call'
      disassembly="$(fixture_disassembly "$target")"
      audit_disassembly \
        'fixture SpectrumMailbox.submit' \
        "$disassembly" \
        '_memcpy _rt_atomic_u8_store_release' \
        '' \
        0
      ;;
    missing-symbol)
      find_unique_symbol \
        '' \
        '^_fixture_callback$' \
        'fixture callback'
      ;;
    ambiguous-symbol)
      find_unique_symbol \
        $'0000000000000000 (__TEXT,__text) external _fixture_callback\n0000000000000004 (__TEXT,__text) external _fixture_callback' \
        '^_fixture_callback$' \
        'fixture callback'
      ;;
    allowed-chain)
      disassembly="$(fixture_disassembly \
        '_objc_msgSend$floatChannelData' \
        '_objc_msgSend$frameLength' \
        '_objc_opt_self' \
        '_$ss3minyxx_xtSLRzlF' \
        '_memcpy' \
        '_rt_atomic_u8_compare_exchange_acq_rel' \
        '_rt_atomic_u8_store_release')"
      audit_disassembly \
        'fixture allowed callback chain' \
        "$disassembly" \
        '_objc_msgSend$floatChannelData _objc_msgSend$frameLength _objc_opt_self _$ss3minyxx_xtSLRzlF _memcpy _rt_atomic_u8_compare_exchange_acq_rel _rt_atomic_u8_store_release' \
        '_objc_msgSend$floatChannelData _objc_msgSend$frameLength _memcpy _rt_atomic_u8_compare_exchange_acq_rel _rt_atomic_u8_store_release' \
        0
      ;;
    *)
      fail "unknown audit fixture: $fixture"
      ;;
  esac
}

fixture_disassembly() {
  local target

  echo '0000000000000000 <_fixture_callback>:'
  for target in "$@"; do
    printf '0000000000000000 ARM64_RELOC_BRANCH26 %s\n' "$target"
  done
}

find_unique_object() {
  local root="$1"
  local name="$2"
  local matches
  local count

  matches="$(
    find "$root" -path "*Objects-normal/arm64/$name" -print
  )" || fail "failed to search for $name"
  count="$(line_count "$matches")"
  if test "$count" -ne 1; then
    fail "$name must resolve exactly once (found $count)"
  fi
  printf '%s\n' "$matches"
}

find_unique_symbol() {
  local symbols="$1"
  local pattern="$2"
  local label="$3"
  local matches
  local count

  matches="$(
    awk -v pattern="$pattern" \
      '$2 == "(__TEXT,__text)" && $NF ~ pattern { print $NF }' \
      <<< "$symbols"
  )"
  count="$(line_count "$matches")"
  if test "$count" -ne 1; then
    echo "$matches" >&2
    fail "$label must resolve exactly once (found $count)"
  fi
  printf '%s\n' "$matches"
}

disassemble_symbol() {
  local object="$1"
  local symbol="$2"
  local output

  output="$(
    xcrun llvm-objdump \
      --disassemble-symbols="$symbol" \
      --reloc \
      "$object"
  )" || fail "failed to disassemble $symbol"
  if ! rg -F -q "<$symbol>:" <<< "$output"; then
    fail "disassembler did not emit $symbol"
  fi
  printf '%s\n' "$output"
}

branch_targets() {
  awk '/ARM64_RELOC_BRANCH26/ { print $NF }' <<< "$1"
}

indirect_branch_count() {
  awk '$3 == "br" || $3 == "blr" { count += 1 } END { print count + 0 }' \
    <<< "$1"
}

audit_function() {
  local label="$1"
  local object="$2"
  local symbol="$3"
  local allowed="$4"
  local required="$5"
  local expected_indirect="$6"
  local disassembly

  disassembly="$(disassemble_symbol "$object" "$symbol")"
  audit_disassembly \
    "$label" \
    "$disassembly" \
    "$allowed" \
    "$required" \
    "$expected_indirect"
}

audit_disassembly() {
  local label="$1"
  local disassembly="$2"
  local allowed="$3"
  local required="$4"
  local expected_indirect="$5"
  local targets
  local actual_indirect

  targets="$(branch_targets "$disassembly")"
  audit_target_list "$label" "$targets" "$allowed" "$required"

  actual_indirect="$(indirect_branch_count "$disassembly")"
  if test "$actual_indirect" -ne "$expected_indirect"; then
    fail "$label indirect branch count mismatch: expected $expected_indirect, found $actual_indirect"
  fi
}

require_instruction() {
  local label="$1"
  local disassembly="$2"
  local instruction="$3"

  if ! rg -q "[[:space:]]$instruction[[:space:]]" <<< "$disassembly"; then
    fail "$label is missing required instruction: $instruction"
  fi
}

audit_root() {
  local root="$1"
  local noise_object
  local bridge_object
  local analyzer_object
  local mailbox_object
  local atomics_object
  local configuration
  local object
  local noise_symbols
  local bridge_symbols
  local analyzer_symbols
  local mailbox_symbols
  local atomics_symbols
  local block_invoke
  local forwarder
  local analyzer_init
  local submit_thunk
  local compare_exchange
  local store_release
  local getter_float='_objc_msgSend$floatChannelData'
  local getter_length='_objc_msgSend$frameLength'
  local memcpy_symbol='_memcpy'
  local init_disassembly
  local compare_disassembly
  local store_disassembly

  noise_object="$(find_unique_object "$root" NoiseEngine.o)"
  bridge_object="$(find_unique_object "$root" RealtimeTapBridge.o)"
  analyzer_object="$(find_unique_object "$root" SpectrumAnalyzer.o)"
  mailbox_object="$(find_unique_object "$root" SpectrumMailbox.o)"
  atomics_object="$(find_unique_object "$root" RealtimeAtomics.o)"

  case "$noise_object" in
    *Debug-*) configuration=Debug ;;
    *Release-*) configuration=Release ;;
    *) fail 'unable to determine Debug or Release configuration' ;;
  esac
  for object in \
    "$bridge_object" \
    "$analyzer_object" \
    "$mailbox_object" \
    "$atomics_object"; do
    case "$object" in
      *"$configuration"-*) ;;
      *) fail "object configuration mismatch: $object" ;;
    esac
  done

  noise_symbols="$(nm -nm "$noise_object")"
  bridge_symbols="$(nm -nm "$bridge_object")"
  analyzer_symbols="$(nm -nm "$analyzer_object")"
  mailbox_symbols="$(nm -nm "$mailbox_object")"
  atomics_symbols="$(nm -nm "$atomics_object")"

  audit_noise_symbols "$noise_symbols"
  if test "$(awk '$NF == "_rt_audio_node_install_spectrum_tap" { count += 1 } END { print count + 0 }' <<< "$noise_symbols")" -ne 1; then
    fail 'NoiseEngine.o must reference rt_audio_node_install_spectrum_tap exactly once'
  fi

  block_invoke="$(
    find_unique_symbol \
      "$bridge_symbols" \
      '^___rt_audio_node_install_spectrum_tap_block_invoke$' \
      'spectrum tap block invoke'
  )"
  forwarder="$(
    find_unique_symbol \
      "$bridge_symbols" \
      '^_rt_spectrum_tap_forward$' \
      'spectrum tap forwarder'
  )"
  analyzer_init="$(
    find_unique_symbol \
      "$analyzer_symbols" \
      'SpectrumAnalyzerC10sampleRate10generation12pollInterval.*tcfc$' \
      'SpectrumAnalyzer designated initializer'
  )"
  submit_thunk="$(
    find_unique_symbol \
      "$analyzer_symbols" \
      'SpectrumAnalyzerC.*SbSv_SPySfGSitYbcfU_To$' \
      'capture-free spectrum submit C thunk'
  )"
  compare_exchange="$(
    find_unique_symbol \
      "$atomics_symbols" \
      '^_rt_atomic_u8_compare_exchange_acq_rel$' \
      'atomic compare-exchange helper'
  )"
  store_release="$(
    find_unique_symbol \
      "$atomics_symbols" \
      '^_rt_atomic_u8_store_release$' \
      'atomic release-store helper'
  )"

  audit_function \
    'spectrum tap block invoke' \
    "$bridge_object" \
    "$block_invoke" \
    "$forwarder" \
    "$forwarder" \
    0
  audit_function \
    'spectrum tap forwarder' \
    "$bridge_object" \
    "$forwarder" \
    "$getter_float $getter_length" \
    "$getter_float $getter_length" \
    1

  init_disassembly="$(disassemble_symbol "$analyzer_object" "$analyzer_init")"
  if ! rg -F -q "$submit_thunk" <<< "$init_disassembly"; then
    fail 'SpectrumAnalyzer initializer does not install the audited submit thunk'
  fi

  if test "$configuration" = Debug; then
    local submit_body
    local mailbox_metadata
    local mailbox_submit
    local copy_and_publish
    local publish_accumulator
    local finish_publish
    local sample_count
    local ready
    local writing
    local free
    local minimum='_$ss3minyxx_xtSLRzlF'
    local objc_opt_self='_objc_opt_self'

    submit_body="$(
      find_unique_symbol \
        "$analyzer_symbols" \
        'SpectrumAnalyzerC.*SbSv_SPySfGSitYbcfU_$' \
        'Debug spectrum submit closure body'
    )"
    mailbox_metadata="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxCMa$' \
        'Debug SpectrumMailbox metadata helper'
    )"
    mailbox_submit="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC6submit.*FZ$' \
        'Debug SpectrumMailbox.submit'
    )"
    copy_and_publish="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC14copyAndPublish.*FZ$' \
        'Debug SpectrumMailbox.copyAndPublish'
    )"
    publish_accumulator="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC18publishAccumulator.*FZ$' \
        'Debug SpectrumMailbox.publishAccumulator'
    )"
    finish_publish="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC13finishPublish.*FZ$' \
        'Debug SpectrumMailbox.finishPublish'
    )"
    sample_count="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC11sampleCountSivau$' \
        'Debug SpectrumMailbox.sampleCount accessor'
    )"
    ready="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC5ready.*vau$' \
        'Debug SpectrumMailbox.ready accessor'
    )"
    writing="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC7writing.*vau$' \
        'Debug SpectrumMailbox.writing accessor'
    )"
    free="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC4free.*vau$' \
        'Debug SpectrumMailbox.free accessor'
    )"

    audit_function \
      'Debug spectrum submit C thunk' \
      "$analyzer_object" \
      "$submit_thunk" \
      "$submit_body" \
      "$submit_body" \
      0
    audit_function \
      'Debug spectrum submit closure body' \
      "$analyzer_object" \
      "$submit_body" \
      "$mailbox_metadata $mailbox_submit" \
      "$mailbox_metadata $mailbox_submit" \
      0
    audit_function \
      'Debug SpectrumMailbox metadata helper' \
      "$mailbox_object" \
      "$mailbox_metadata" \
      "$objc_opt_self" \
      "$objc_opt_self" \
      0
    audit_function \
      'Debug SpectrumMailbox.submit' \
      "$mailbox_object" \
      "$mailbox_submit" \
      "$copy_and_publish" \
      "$copy_and_publish" \
      0
    audit_function \
      'Debug SpectrumMailbox.copyAndPublish' \
      "$mailbox_object" \
      "$copy_and_publish" \
      "$minimum $memcpy_symbol $sample_count $publish_accumulator" \
      "$minimum $memcpy_symbol $sample_count $publish_accumulator" \
      0
    audit_function \
      'Debug SpectrumMailbox.publishAccumulator' \
      "$mailbox_object" \
      "$publish_accumulator" \
      "$compare_exchange $finish_publish $ready $writing $free" \
      "$compare_exchange $finish_publish $ready $writing $free" \
      0
    audit_function \
      'Debug SpectrumMailbox.finishPublish' \
      "$mailbox_object" \
      "$finish_publish" \
      "$memcpy_symbol $store_release" \
      "$memcpy_symbol $store_release" \
      0
    audit_function \
      'Debug SpectrumMailbox.sampleCount accessor' \
      "$mailbox_object" \
      "$sample_count" \
      '' \
      '' \
      0
    audit_function \
      'Debug SpectrumMailbox.ready accessor' \
      "$mailbox_object" \
      "$ready" \
      '' \
      '' \
      0
    audit_function \
      'Debug SpectrumMailbox.writing accessor' \
      "$mailbox_object" \
      "$writing" \
      '' \
      '' \
      0
    audit_function \
      'Debug SpectrumMailbox.free accessor' \
      "$mailbox_object" \
      "$free" \
      '' \
      '' \
      0
  else
    local mailbox_submit
    local publish_accumulator

    mailbox_submit="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC6submit.*Tf4nnnd_n$' \
        'Release specialized SpectrumMailbox.submit'
    )"
    publish_accumulator="$(
      find_unique_symbol \
        "$mailbox_symbols" \
        'SpectrumMailboxC18publishAccumulator.*Tf4nd_n$' \
        'Release specialized SpectrumMailbox.publishAccumulator'
    )"

    audit_function \
      'Release spectrum submit C thunk' \
      "$analyzer_object" \
      "$submit_thunk" \
      "$mailbox_submit" \
      "$mailbox_submit" \
      0
    audit_function \
      'Release SpectrumMailbox.submit with inlined copyAndPublish' \
      "$mailbox_object" \
      "$mailbox_submit" \
      "$memcpy_symbol $publish_accumulator" \
      "$memcpy_symbol $publish_accumulator" \
      0
    audit_function \
      'Release SpectrumMailbox.publishAccumulator with inlined finishPublish' \
      "$mailbox_object" \
      "$publish_accumulator" \
      "$compare_exchange $memcpy_symbol $store_release" \
      "$compare_exchange $memcpy_symbol $store_release" \
      0
  fi

  audit_function \
    "$configuration atomic compare-exchange helper" \
    "$atomics_object" \
    "$compare_exchange" \
    '' \
    '' \
    0
  audit_function \
    "$configuration atomic release-store helper" \
    "$atomics_object" \
    "$store_release" \
    '' \
    '' \
    0
  compare_disassembly="$(
    disassemble_symbol "$atomics_object" "$compare_exchange"
  )"
  store_disassembly="$(
    disassemble_symbol "$atomics_object" "$store_release"
  )"
  require_instruction \
    "$configuration atomic compare-exchange helper" \
    "$compare_disassembly" \
    ldaxrb
  require_instruction \
    "$configuration atomic compare-exchange helper" \
    "$compare_disassembly" \
    stlxrb
  require_instruction \
    "$configuration atomic release-store helper" \
    "$store_disassembly" \
    stlrb

  echo "realtime tap callback-chain audit ($configuration): PASS"
}

if test "${1:-}" = --fixture; then
  test "$#" -eq 2 || fail 'usage: audit-realtime-tap.sh --fixture NAME'
  run_fixture "$2"
  exit 0
fi

test "$#" -eq 1 || fail 'usage: audit-realtime-tap.sh DERIVED_DATA_ROOT'
audit_root "$1"
