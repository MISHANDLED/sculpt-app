#if defined(OBJECT_NOISE_ENGINE)

.section __TEXT,__text,regular,pure_instructions
.globl _fixture_noise_engine_install
.p2align 2
_fixture_noise_engine_install:
    bl _rt_audio_node_install_spectrum_tap
    ret

#if defined(MALFORMED_SWIFT_SYMBOL)
.globl "_$sMalformedTapThunk"
.p2align 2
"_$sMalformedTapThunk":
    ret
#endif

#elif defined(OBJECT_REALTIME_TAP_BRIDGE)

.section __TEXT,__text,regular,pure_instructions
.globl ___rt_audio_node_install_spectrum_tap_block_invoke
.p2align 2
___rt_audio_node_install_spectrum_tap_block_invoke:
    bl _rt_spectrum_tap_forward
    ret

.globl _rt_spectrum_tap_forward
.p2align 2
_rt_spectrum_tap_forward:
    bl "_objc_msgSend$floatChannelData"
    bl "_objc_msgSend$frameLength"
#if defined(BRIDGE_OWNERSHIP)
    bl _swift_retain
#endif
#if defined(BRIDGE_INDIRECT)
    br x9
#elif defined(BRIDGE_REGISTER_RETURN)
    bl _rt_spectrum_mailbox_submit
    ret x9
#elif defined(BRIDGE_UNEXPECTED_TAIL)
    bl _rt_spectrum_mailbox_submit
    b _fixture_unexpected_tail
#elif defined(BRIDGE_UNRESOLVED_BRANCH)
    bl _rt_spectrum_mailbox_submit
    .long 0x14000400
#else
    b _rt_spectrum_mailbox_submit
#endif

#elif defined(OBJECT_SPECTRUM_ANALYZER)

.section __TEXT,__text,regular,pure_instructions
.globl _FixtureSpectrumAnalyzerC10sampleRate10generation12pollIntervalSdtcfc
.p2align 2
_FixtureSpectrumAnalyzerC10sampleRate10generation12pollIntervalSdtcfc:
    ret

#elif defined(OBJECT_SPECTRUM_MAILBOX)

.section __TEXT,__text,regular,pure_instructions
#if !defined(MISSING_C_ENTRY)
.globl _rt_spectrum_mailbox_submit
.p2align 2
_rt_spectrum_mailbox_submit:
    b _Fixture_rtSpectrumMailboxSubmitC_F
#endif

.globl _Fixture_rtSpectrumMailboxSubmitC_F
.p2align 2
_Fixture_rtSpectrumMailboxSubmitC_F:
    b _FixtureSpectrumMailboxC6submitTf4nnnd_n

.globl _FixtureSpectrumMailboxC6submitTf4nnnd_n
.p2align 2
_FixtureSpectrumMailboxC6submitTf4nnnd_n:
    b _FixtureSpectrumMailboxC14copyAndPublishTf4nnnd_n

.globl _FixtureSpectrumMailboxC14copyAndPublishTf4nnnd_n
.p2align 2
_FixtureSpectrumMailboxC14copyAndPublishTf4nnnd_n:
    bl _memcpy
#if defined(SUBMIT_ALLOCATION)
    bl _malloc
#endif
#if defined(SUBMIT_LOCK)
    bl _pthread_mutex_lock
#endif
#if defined(SUBMIT_DISPATCH)
    bl _dispatch_async
#endif
#if defined(SUBMIT_UNEXPECTED)
    bl _fixture_unexpected_call
#endif
#if defined(SUBMIT_LOCAL_CALL)
    bl 1f
#endif
    b _FixtureSpectrumMailboxC18publishAccumulatorTf4nd_n
#if defined(SUBMIT_LOCAL_CALL)
1:
    ret
#endif

#if defined(AMBIGUOUS_SUBMIT)
.globl _OtherSpectrumMailboxC6submitTf4nnnd_n
.p2align 2
_OtherSpectrumMailboxC6submitTf4nnnd_n:
    ret
#endif

.globl _FixtureSpectrumMailboxC18publishAccumulatorTf4nd_n
.p2align 2
_FixtureSpectrumMailboxC18publishAccumulatorTf4nd_n:
    bl _rt_atomic_u8_compare_exchange_acq_rel
    bl _memcpy
    bl _rt_atomic_u8_store_release
    ret

#elif defined(OBJECT_REALTIME_ATOMICS)

.section __TEXT,__text,regular,pure_instructions
.globl _rt_atomic_u8_compare_exchange_acq_rel
.p2align 2
_rt_atomic_u8_compare_exchange_acq_rel:
1:
    ldaxrb w8, [x0]
    cmp w8, w1
    b.ne 2f
    stlxrb w9, w2, [x0]
    cbnz w9, 1b
    mov w0, #1
    ret
2:
    mov w0, #0
    ret

.globl _rt_atomic_u8_store_release
.p2align 2
_rt_atomic_u8_store_release:
    stlrb w1, [x0]
    ret

#else
#error Select exactly one fixture object
#endif

.subsections_via_symbols
