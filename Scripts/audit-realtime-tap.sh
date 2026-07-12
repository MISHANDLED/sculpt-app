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

find_unique_object() {
  local root="$1"
  local name="$2"
  local matches
  local count

  matches="$(find "$root" -path "*Objects-normal/arm64/$name" -print)" \
    || fail "failed to search for $name"
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
    test -z "$matches" || printf '%s\n' "$matches" >&2
    fail "$label must resolve exactly once (found $count)"
  fi
  printf '%s\n' "$matches"
}

require_no_symbol() {
  local symbols="$1"
  local pattern="$2"
  local label="$3"
  local matches

  matches="$(
    awk -v pattern="$pattern" \
      '$2 == "(__TEXT,__text)" && $NF ~ pattern { print $NF }' \
      <<< "$symbols"
  )"
  if test -n "$matches"; then
    printf '%s\n' "$matches" >&2
    fail "$label must not be present"
  fi
}

audit_noise_symbols() {
  local symbols="$1"
  local swift_symbols
  local demangled

  swift_symbols="$(
    awk '$2 == "(__TEXT,__text)" && $NF ~ /^_?\$s/ { print $NF }' \
      <<< "$symbols"
  )"
  if rg -q 'AVAudioPCMBuffer|AVAudioTime' <<< "$swift_symbols"; then
    fail 'Swift AVAudioPCMBuffer or AVAudioTime callback thunk is still present'
  fi
  test -z "$swift_symbols" && return

  demangled="$(xcrun swift-demangle --compact <<< "$swift_symbols")" \
    || fail 'failed to demangle NoiseEngine Swift text symbols'
  if test "$(line_count "$demangled")" -ne "$(line_count "$swift_symbols")"; then
    fail 'NoiseEngine Swift text symbol demangling was incomplete'
  fi
  if rg -q 'AVAudioPCMBuffer|AVAudioTime' <<< "$demangled"; then
    fail 'Swift AVAudioPCMBuffer or AVAudioTime callback thunk is still present'
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

branch_records() {
  local symbol="$1"
  local disassembly="$2"

  awk -v symbol="$symbol" '
    function hex_value(character, position) {
      character = tolower(character)
      position = index("0123456789abcdef", character)
      return position - 1
    }
    function hex_to_number(value, result, index_value) {
      sub(/^0x/, "", value)
      result = 0
      for (index_value = 1; index_value <= length(value); index_value++) {
        result = (result * 16) + hex_value(substr(value, index_value, 1))
      }
      return result
    }
    function clean_address(value) {
      sub(/:$/, "", value)
      sub(/^0+/, "", value)
      if (value == "") value = "0"
      return value
    }
    function clean_operand(value) {
      gsub(/,/, "", value)
      return value
    }
    function annotation_target(count, fields, index_value, value) {
      for (index_value = 1; index_value <= count; index_value++) {
        value = fields[index_value]
        if (value ~ /^<.*>$/) {
          sub(/^</, "", value)
          sub(/>$/, "", value)
          sub(/\+0x[0-9a-fA-F]+$/, "", value)
          return value
        }
      }
      return ""
    }
    {
      lines[NR] = $0
      if ($2 == "ARM64_RELOC_BRANCH26") {
        relocation[clean_address($1)] = $NF
      } else if ($1 ~ /^[0-9a-fA-F]+:$/ && $2 ~ /^[0-9a-fA-F]+$/) {
        address = hex_to_number(clean_address($1))
        if (!have_instruction || address < minimum) minimum = address
        if (!have_instruction || address > maximum) maximum = address
        have_instruction = 1
      }
    }
    END {
      for (line_number = 1; line_number <= NR; line_number++) {
        count = split(lines[line_number], fields)
        if (count < 3 || fields[1] !~ /^[0-9a-fA-F]+:$/ ||
            fields[2] !~ /^[0-9a-fA-F]+$/) {
          continue
        }
        mnemonic = fields[3]
        is_direct = mnemonic == "b" || mnemonic == "bl"
        is_conditional = mnemonic ~ /^b\./ || mnemonic ~ /^bc\./ ||
          mnemonic == "cbz" || mnemonic == "cbnz" ||
          mnemonic == "tbz" || mnemonic == "tbnz"
        is_indirect = mnemonic == "br" || mnemonic == "blr" ||
          mnemonic == "braa" || mnemonic == "braaz" ||
          mnemonic == "brab" || mnemonic == "brabz" ||
          mnemonic == "blraa" || mnemonic == "blraaz" ||
          mnemonic == "blrab" || mnemonic == "blrabz"
        if (!is_direct && !is_conditional && !is_indirect) continue

        address_text = clean_address(fields[1])
        if (is_indirect) {
          printf "INDIRECT\t%s\t%s\n", mnemonic, fields[4]
          continue
        }

        target_number = -1
        for (field_number = 4; field_number <= count; field_number++) {
          operand = clean_operand(fields[field_number])
          if (operand ~ /^0x[0-9a-fA-F]+$/) {
            target_number = hex_to_number(operand)
          }
        }
        target = relocation[address_text]
        if (target != "") {
          if (is_conditional) {
            printf "UNRESOLVED\t%s\t%s\n", mnemonic, target
          } else {
            printf "TARGET\t%s\n", target
          }
          continue
        }

        if (target_number >= minimum && target_number <= maximum) {
          if (mnemonic == "bl") {
            printf "LOCAL_CALL\tbl\t0x%x\n", target_number
          }
          continue
        }

        target = annotation_target(count, fields)
        if (is_conditional || target == "" || target == symbol) {
          printf "UNRESOLVED\t%s\t0x%x\n", mnemonic, target_number
        } else {
          printf "TARGET\t%s\n", target
        }
      }
    }
  ' <<< "$disassembly"
}

audit_function() {
  local label="$1"
  local object="$2"
  local symbol="$3"
  local allowed="$4"
  local required="$5"
  local disassembly
  local records
  local targets=''
  local kind
  local value
  local detail
  local target

  disassembly="$(disassemble_symbol "$object" "$symbol")"
  records="$(branch_records "$symbol" "$disassembly")"
  while IFS=$'\t' read -r kind value detail; do
    test -z "$kind" && continue
    case "$kind" in
      TARGET)
        target="$value"
        classify_branch_target "$label" "$target"
        if ! list_contains "$target" "$allowed"; then
          fail "unexpected branch target in $label: $target"
        fi
        targets="$targets $target"
        ;;
      LOCAL_CALL)
        fail "unexpected local call in $label: $value $detail"
        ;;
      INDIRECT)
        fail "forbidden indirect branch in $label: $value $detail"
        ;;
      UNRESOLVED)
        fail "unresolved or external control transfer in $label: $value $detail"
        ;;
      *) fail "unknown branch record in $label: $kind" ;;
    esac
  done <<< "$records"

  for target in $required; do
    if ! list_contains "$target" "$targets"; then
      fail "expected branch target missing from $label: $target"
    fi
  done
}

require_instruction() {
  local label="$1"
  local disassembly="$2"
  local instruction="$3"

  if ! rg -q "[[:space:]]${instruction}[[:space:]]" <<< "$disassembly"; then
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
  local c_entry
  local submit_body
  local mailbox_submit
  local publish_accumulator
  local compare_exchange
  local store_release
  local getter_float='_objc_msgSend$floatChannelData'
  local getter_length='_objc_msgSend$frameLength'
  local memcpy_symbol='_memcpy'
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
  for object in "$bridge_object" "$analyzer_object" "$mailbox_object" "$atomics_object"; do
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
  require_no_symbol \
    "$analyzer_symbols" \
    'SbSv_SPySfGSitYbc' \
    'dynamic spectrum submit C thunk'

  block_invoke="$(find_unique_symbol "$bridge_symbols" '^___rt_audio_node_install_spectrum_tap_block_invoke$' 'spectrum tap block invoke')"
  forwarder="$(find_unique_symbol "$bridge_symbols" '^_rt_spectrum_tap_forward$' 'spectrum tap forwarder')"
  analyzer_init="$(find_unique_symbol "$analyzer_symbols" 'SpectrumAnalyzerC10sampleRate10generation12pollInterval.*tcfc$' 'SpectrumAnalyzer designated initializer')"
  c_entry="$(find_unique_symbol "$mailbox_symbols" '^_rt_spectrum_mailbox_submit$' 'fixed spectrum mailbox C entry')"
  submit_body="$(find_unique_symbol "$mailbox_symbols" 'rtSpectrumMailboxSubmitC.*F$' 'fixed spectrum mailbox Swift body')"
  compare_exchange="$(find_unique_symbol "$atomics_symbols" '^_rt_atomic_u8_compare_exchange_acq_rel$' 'atomic compare-exchange helper')"
  store_release="$(find_unique_symbol "$atomics_symbols" '^_rt_atomic_u8_store_release$' 'atomic release-store helper')"
  test -n "$analyzer_init"

  audit_function 'spectrum tap block invoke' "$bridge_object" "$block_invoke" "$forwarder" "$forwarder"
  audit_function 'spectrum tap forwarder' "$bridge_object" "$forwarder" "$getter_float $getter_length $c_entry" "$getter_float $getter_length $c_entry"
  audit_function 'fixed spectrum mailbox C entry' "$mailbox_object" "$c_entry" "$submit_body" "$submit_body"

  if test "$configuration" = Debug; then
    local mailbox_metadata
    local copy_and_publish
    local finish_publish
    local sample_count
    local ready
    local writing
    local free
    local objc_opt_self='_objc_opt_self'

    mailbox_metadata="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxCMa$' 'Debug SpectrumMailbox metadata helper')"
    mailbox_submit="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC6submit.*FZ$' 'Debug SpectrumMailbox.submit')"
    copy_and_publish="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC14copyAndPublish.*FZ$' 'Debug SpectrumMailbox.copyAndPublish')"
    publish_accumulator="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC18publishAccumulator.*FZ$' 'Debug SpectrumMailbox.publishAccumulator')"
    finish_publish="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC13finishPublish.*FZ$' 'Debug SpectrumMailbox.finishPublish')"
    sample_count="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC11sampleCountSivau$' 'Debug SpectrumMailbox.sampleCount accessor')"
    ready="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC5ready.*vau$' 'Debug SpectrumMailbox.ready accessor')"
    writing="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC7writing.*vau$' 'Debug SpectrumMailbox.writing accessor')"
    free="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC4free.*vau$' 'Debug SpectrumMailbox.free accessor')"

    audit_function 'Debug fixed spectrum mailbox Swift body' "$mailbox_object" "$submit_body" "$mailbox_metadata $mailbox_submit" "$mailbox_metadata $mailbox_submit"
    audit_function 'Debug SpectrumMailbox metadata helper' "$mailbox_object" "$mailbox_metadata" "$objc_opt_self" "$objc_opt_self"
    audit_function 'Debug SpectrumMailbox.submit' "$mailbox_object" "$mailbox_submit" "$copy_and_publish" "$copy_and_publish"
    audit_function 'Debug SpectrumMailbox.copyAndPublish' "$mailbox_object" "$copy_and_publish" "$memcpy_symbol $sample_count $publish_accumulator" "$memcpy_symbol $sample_count $publish_accumulator"
    audit_function 'Debug SpectrumMailbox.publishAccumulator' "$mailbox_object" "$publish_accumulator" "$compare_exchange $finish_publish $ready $writing $free" "$compare_exchange $finish_publish $ready $writing $free"
    audit_function 'Debug SpectrumMailbox.finishPublish' "$mailbox_object" "$finish_publish" "$memcpy_symbol $store_release" "$memcpy_symbol $store_release"
    audit_function 'Debug SpectrumMailbox.sampleCount accessor' "$mailbox_object" "$sample_count" '' ''
    audit_function 'Debug SpectrumMailbox.ready accessor' "$mailbox_object" "$ready" '' ''
    audit_function 'Debug SpectrumMailbox.writing accessor' "$mailbox_object" "$writing" '' ''
    audit_function 'Debug SpectrumMailbox.free accessor' "$mailbox_object" "$free" '' ''
  else
    local copy_and_publish

    mailbox_submit="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC6submit.*Tf4nnnd_n$' 'Release specialized SpectrumMailbox.submit')"
    copy_and_publish="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC14copyAndPublish.*Tf4nnnd_n$' 'Release specialized SpectrumMailbox.copyAndPublish')"
    publish_accumulator="$(find_unique_symbol "$mailbox_symbols" 'SpectrumMailboxC18publishAccumulator.*Tf4nd_n$' 'Release specialized SpectrumMailbox.publishAccumulator')"

    audit_function 'Release fixed spectrum mailbox Swift body' "$mailbox_object" "$submit_body" "$mailbox_submit" "$mailbox_submit"
    audit_function 'Release SpectrumMailbox.submit' "$mailbox_object" "$mailbox_submit" "$copy_and_publish" "$copy_and_publish"
    audit_function 'Release SpectrumMailbox.copyAndPublish' "$mailbox_object" "$copy_and_publish" "$memcpy_symbol $publish_accumulator" "$memcpy_symbol $publish_accumulator"
    audit_function 'Release SpectrumMailbox.publishAccumulator with inlined finishPublish' "$mailbox_object" "$publish_accumulator" "$compare_exchange $memcpy_symbol $store_release" "$compare_exchange $memcpy_symbol $store_release"
  fi

  audit_function "$configuration atomic compare-exchange helper" "$atomics_object" "$compare_exchange" '' ''
  audit_function "$configuration atomic release-store helper" "$atomics_object" "$store_release" '' ''
  compare_disassembly="$(disassemble_symbol "$atomics_object" "$compare_exchange")"
  store_disassembly="$(disassemble_symbol "$atomics_object" "$store_release")"
  require_instruction "$configuration atomic compare-exchange helper" "$compare_disassembly" ldaxrb
  require_instruction "$configuration atomic compare-exchange helper" "$compare_disassembly" stlxrb
  require_instruction "$configuration atomic release-store helper" "$store_disassembly" stlrb

  echo "realtime tap callback-chain audit ($configuration): PASS"
}

test "$#" -eq 1 || fail 'usage: audit-realtime-tap.sh DERIVED_DATA_ROOT'
audit_root "$1"
