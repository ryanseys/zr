# frozen_string_literal: true

module Ze0
  # The runtime entry points the subset calls, as CLIF signature text.
  #
  # Each row transcribes one of crates/zeo/src/clif/capi_names.rs. `zeo
  # backend` compares every call against that table, so a row that drifts
  # fails the build by name rather than the program by crash.
  module Capi
    SIGS = {
      "zeo_rt_frame_enter" => [%w[i64 i64 i64 i64 i32 i32], "i32"],
      "zeo_rt_frame_push" => [%w[i64 i64 i64 i64 i32 i32], nil],
      "zeo_rt_frame_pop" => [[], nil],
      "zeo_rt_set_line" => [%w[i32], nil],
      "zeo_rt_check_ints" => [[], "i32"],
      "zeo_rt_stack_check" => [[], "i32"],
      "zeo_rt_main_object" => [%w[i64], nil],
      "zeo_rt_probe_def_hook" => [["i32", "i8 uext", "i8 uext", "i32", "i64", "i64"], "i32"],
      "zeo_rt_pool_mark" => [[], "i64"],
      "zeo_rt_pool_reset" => [%w[i64], nil],
      "zeo_rt_pool_push" => [%w[i64], nil],
      "zeo_rt_reveal_class" => [%w[i32], nil],
      "zeo_rt_retain" => [%w[i64], nil],
      "zeo_rt_release" => [%w[i64], nil],
      "zeo_rt_truthy" => [%w[i64], "i8"],
      "zeo_rt_str_lit" => [["i64", "i64", "i8 uext", "i64"], nil],
      "zeo_rt_str_lit_ro" => [["i64", "i64", "i8 uext", "i64"], nil],
      "zeo_rt_kernel_puts" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_send_value_cached" => [%w[i64 i32 i64 i32 i64 i64 i64 i64], "i32"],
      "zeo_rt_send_value_kw_cached" => [%w[i64 i32 i64 i32 i64 i64 i64 i64 i64], "i32"],
      "zeo_rt_send_value_vcall_cached" => [%w[i64 i32 i64 i32 i64], "i32"],
      # The uncached shapes: the same sends with the caller class as an
      # argument rather than in a site, for a body whose `self` only the
      # run time knows.
      "zeo_rt_send_value_explicit_in" => [%w[i32 i64 i32 i64 i64 i64 i32 i64], "i32"],
      "zeo_rt_send_value_explicit_kw_in" => [%w[i32 i64 i32 i64 i64 i64 i64 i32 i64], "i32"],
      "zeo_rt_class_of" => [%w[i64], "i32"],
      "zeo_rt_int_add_slow" => [%w[i64 i64 i64], nil],
      "zeo_rt_int_sub_slow" => [%w[i64 i64 i64], nil],
      "zeo_rt_int_mul_slow" => [%w[i64 i64 i64], nil],
      "zeo_rt_wrong_arity" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_str_new" => [["i64", "i64", "i8 uext", "i64"], nil],
      "zeo_rt_str_append_lit" => [%w[i64 i64 i64], nil],
      "zeo_rt_str_append_value" => [%w[i64 i64], "i32"],
      "zeo_rt_array_new" => [%w[i64 i64], nil],
      "zeo_rt_array_push" => [%w[i64 i64], nil],
      "zeo_rt_hash_new" => [%w[i64], nil],
      "zeo_rt_hash_set" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_range_new" => [["i64", "i64", "i8 uext", "i64"], "i32"],
      "zeo_rt_gvar_alias" => [%w[i32 i64 i64 i64 i64], nil],
      "zeo_rt_gvar_get" => [%w[i32 i64 i64 i64], nil],
      "zeo_rt_gvar_assign" => [%w[i32 i64 i64 i64], "i32"],
      "zeo_rt_autoload_touch" => [["i32", "i64", "i64"], "i32"],
      "zeo_rt_autoload_touch_value" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_binding_new" => [%w[i64 i64 i64 i64 i64 i64 i32 i32 i32 i64], nil],
      "zeo_rt_const_get_cref" => [["i64", "i64", "i64", "i64", "i64", "i64", "i8 uext", "i32", "i64"], "i32"],
      "zeo_rt_const_get_on_value" => [%w[i64 i64 i64 i64 i64 i64], "i32"],
      "zeo_rt_const_set_at" => [%w[i32 i64 i64 i64 i64 i64 i32 i32], nil],
      "zeo_rt_cvar_get" => [%w[i32 i64 i64 i64], nil],
      "zeo_rt_cvar_get_checked" => [%w[i32 i64 i64 i64], "i32"],
      "zeo_rt_cvar_set" => [%w[i32 i64 i64 i64], "i32"],
      "zeo_rt_ivar_get_dyn" => [%w[i64 i64 i64 i32 i64], "i32"],
      "zeo_rt_ivar_set_dyn" => [%w[i64 i64 i64 i32 i64], "i32"],
      "zeo_rt_ivar_get_slot" => [%w[i64 i64 i64], nil],
      "zeo_rt_ivar_set_slot" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_frozen_check" => [%w[i64], "i32"],
      "zeo_rt_runtime_set_visibility" => [["i32", "i32", "i8 uext"], "i32"],
      "zeo_rt_send_value_args_cached" => [
        ["i64", "i32", "i64", "i32", "i64", "i8 uext", "i64", "i64", "i64"], "i32",
      ],
      "zeo_rt_send_value_explicit_args_in" => [
        ["i32", "i64", "i32", "i64", "i8 uext", "i64", "i64", "i32", "i64"], "i32",
      ],
      "zeo_rt_bare_super_outside_a_method" => [[], "i32"],
      "zeo_rt_super_defined" => [%w[i64 i32 i32], "i8"],
      "zeo_rt_super_defined_dynamic" => [%w[i64], "i8"],
      "zeo_rt_send_super_class_from_args" => [
        ["i32", "i32", "i32", "i64", "i8 uext", "i64", "i64", "i64"], "i32",
      ],
      "zeo_rt_send_super_from_args" => [
        ["i64", "i32", "i32", "i64", "i8 uext", "i64", "i64", "i64"], "i32",
      ],
      "zeo_rt_case_eq" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_bind_block_params" => [["i64", "i8 uext", "i64", "i64", "i64", "i64"], "i32"],
      "zeo_rt_bind_params" => [%w[i64 i64 i64 i64 i64], "i32"],
      "zeo_rt_signal_set" => [["i8 uext", "i64"], nil],
      "zeo_rt_signal_kind" => [[], "i8"],
      "zeo_rt_signal_take" => [%w[i64], "i8"],
      "zeo_rt_rescue_matches_any" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_handling_push" => [%w[i64], nil],
      "zeo_rt_handling_pop" => [[], nil],
      "zeo_rt_signal_save" => [[], "i64"],
      "zeo_rt_signal_restore" => [%w[i64], nil],
      "zeo_rt_signal_drop" => [%w[i64], nil],
      "zeo_rt_propagating_enter" => [%w[i64], "i8"],
      "zeo_rt_propagating_leave" => [["i8 uext"], nil],
      "zeo_rt_last_match_ref" => [["i8 uext", "i64", "i64"], nil],
      "zeo_rt_pat_array_get" => [%w[i64 i64 i64], nil],
      "zeo_rt_pat_array_len" => [%w[i64], "i64"],
      "zeo_rt_pat_array_slice" => [%w[i64 i64 i64 i64], nil],
      "zeo_rt_pat_deconstruct" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_pat_deconstruct_keys" => [%w[i64 i64 i64 i64 i64], "i32"],
      "zeo_rt_pat_fail_case_eq" => [%w[i64 i64], nil],
      "zeo_rt_pat_fail_find" => [%w[i64], nil],
      "zeo_rt_pat_fail_guard" => [[], nil],
      "zeo_rt_pat_fail_length" => [["i64", "i64", "i8 uext"], nil],
      "zeo_rt_pat_fail_not_empty" => [["i64", "i8 uext"], nil],
      "zeo_rt_pat_hash_except" => [%w[i64 i64 i64 i64], nil],
      "zeo_rt_pat_hash_get" => [["i64", "i32", "i64"], nil],
      "zeo_rt_pat_hash_has_key" => [["i64", "i32"], "i8"],
      "zeo_rt_pat_hash_len" => [%w[i64], "i64"],
      "zeo_rt_pat_key_miss_clear" => [[], nil],
      "zeo_rt_pat_key_miss_record" => [["i32", "i64"], nil],
      "zeo_rt_pat_match_error" => [%w[i64], "i32"],
      "zeo_rt_pat_match_error_bare" => [%w[i64], "i32"],
      "zeo_rt_int_digits" => [["i8 uext", "i64", "i64", "i64"], nil],
      "zeo_rt_rational_digits" => [["i8 uext", "i64", "i64", "i64", "i64", "i64"], nil],
      "zeo_rt_complex_lit" => [%w[i64 i64], nil],
      "zeo_rt_regexp_interp" => [["i64", "i8 uext", "i8 uext", "i8 uext", "i8 uext", "i64"], "i32"],
      "zeo_rt_flip_flop_on" => [%w[i32], "i8"],
      "zeo_rt_flip_flop_set" => [["i32", "i8 uext"], nil],
      "zeo_rt_for_begin" => [["i64", "i8 uext", "i64"], "i32"],
      "zeo_rt_for_next" => [%w[i64 i64 i64], nil],
      "zeo_rt_for_result" => [%w[i64 i64], nil],
      "zeo_rt_for_end" => [%w[i64], nil],
      "zeo_rt_svar_scope_push" => [[], nil],
      "zeo_rt_svar_scope_pop" => [[], nil],
      "zeo_rt_home_push" => [[], nil],
      "zeo_rt_home_pop" => [[], nil],
      "zeo_rt_return_targets_here" => [[], "i8"],
      "zeo_rt_array_push_splat" => [%w[i64 i64], "i32"],
      "zeo_rt_kw_splat_into" => [%w[i64 i64], "i32"],
      "zeo_rt_defined_ivar" => [%w[i64 i64 i64 i64], "i32"],
      "zeo_rt_defined_cvar" => [["i32", "i64", "i64"], "i8"],
      "zeo_rt_defined_gvar" => [["i32", "i64", "i64"], "i8"],
      "zeo_rt_defined_method" => [["i64", "i32", "i8 uext", "i64"], nil],
      "zeo_rt_alias_in_default_definee" => [%w[i64 i64 i64 i64 i64], "i32"],
      "zeo_rt_feature_loaded" => [%w[i32 i64 i64 i64 i64], nil],
      "zeo_rt_const_private" => [["i32", "i64", "i64"], "i8"],
      "zeo_rt_raise_private_constant" => [["i32", "i64", "i64", "i64", "i64"], "i32"],
      "zeo_rt_cell_new" => [%w[i64], "i64"],
      "zeo_rt_cell_load" => [%w[i64 i64], nil],
      "zeo_rt_cell_store" => [%w[i64 i64], nil],
      "zeo_rt_cell_release" => [%w[i64], nil],
      "zeo_rt_yield" => [%w[i64 i64 i64 i64], "i32"],
      "zeo_rt_yield_args" => [%w[i64 i64 i64 i64], "i32"],
      "zeo_rt_send_super_dynamic_args" => [
        ["i64", "i64", "i8 uext", "i64", "i64", "i64"], "i32",
      ],
      "zeo_rt_define_in_default_definee" => [
        ["i64", "i64", "i32", "i64", "i8 uext", "i8 uext", "i64"], "i32",
      ],
      "zeo_rt_block_arg_to_proc" => [%w[i64 i64], "i32"],
      "zeo_rt_multi_split" => [["i64", "i64", "i8 uext", "i64", "i64"], "i32"],
      "zeo_rt_regexp_lit" => [
        ["i32", "i64", "i64", "i8 uext", "i8 uext", "i8 uext", "i8 uext", "i64"], "i32",
      ],
      "zeo_rt_using_slots_ensure" => [%w[i32], nil],
      "zeo_rt_eval_using" => [%w[i64 i32], "i32"],
      "zeo_rt_eval_refined_send" => [
        ["i32", "i64", "i32", "i64", "i64", "i64", "i64", "i64", "i64", "i8 uext", "i64"], "i32",
      ],
      "zeo_rt_eval_refined_send_args" => [
        ["i32", "i64", "i32", "i64", "i8 uext", "i64", "i64", "i64", "i64", "i8 uext", "i64"], "i32",
      ],
      "zeo_rt_eval_reflect_dispatch" => [
        ["i32", "i64", "i8 uext", "i64", "i64", "i64", "i64", "i64", "i64"], "i32",
      ],
      "zeo_rt_ractor_new" => [%w[i64 i64 i64 i64 i64 i64 i64], "i32"],
      "zeo_rt_proc_new" => [
        %w[i64 i64 i64 i64 i64 i64 i32 i32 i64 i64 i64 i64 i32 i64 i64 i64], nil,
      ],
    }.freeze

    # A value slot: the tag byte, then the payload at +8.
    SLOT_BYTES = 24
    # One `zeo_abi::abi::Str`: a rodata pointer, then its length.
    STR_BYTES = 16
    # `zeo_abi`'s tags for the immediates the subset writes; anything at
    # or above HEAP is a refcounted object.
    TAG_NIL = 0
    TAG_BOOL = 1
    TAG_INT = 2
    TAG_FLOAT = 3
    TAG_SYMBOL = 4
    TAG_CLASS = 5
    TAG_HEAP = 16
    # One inline-cache slot (`zeo_abi::abi::CALLSITE_SIZE`).
    CALLSITE_BYTES = 56
    # The encoding index a string literal carries (UTF-8).
    UTF8 = 1
    # A regexp's encoding is its OWN scale, not a string literal's: the
    # default is the source encoding, and the four suffixes follow.
    REGEXP_ENCODINGS = { source: 0, none: 1, euc_jp: 2, windows_31j: 3, utf_8: 4 }.freeze
    # `zeo_abi`'s `OBJECT_CLASS`: the whole cref chain of a top-level
    # constant read, until classes give ze0 a chain to walk.
    OBJECT_CLASS = 0
    # ze0 compiles the main program, which is box 0.
    MAIN_BOX = 0
    # `zeo_rt_bind_block_params`' flags: a single Array argument spreads
    # over a shape with real positional structure.
    BLOCK_BIND_AUTO_SPLAT = 1
    # `zeo_rt_bind_block_params`' other flag, and `zeo_rt_proc_new`'s: a
    # lambda binds strictly and answers a lambda's arity.
    BLOCK_BIND_LAMBDA = 2
    PROC_LAMBDA = 1
    # `zeo_rt_proc_new`'s other bit: a homed proc holds the method
    # activation a `return` written in it unwinds to.
    PROC_HOME = 2
    # `ParamC::kind` for a required positional.
    PARAM_REQ = 0
    # `ParamC::kind` by name, in `zeo_abi`'s declaration order.
    PARAM_KINDS = %w[req opt rest keyreq key keyrest block].freeze
    # `ParamDescC`'s `rest`/`kwrest`: absent, `*`, or `*named`.
    PARAM_STAR_NONE = 0
    PARAM_STAR_ANON = 1
    PARAM_STAR_NAMED = 2
    # `ProcEnv.lexical_blk`: the enclosing method's block, which a bare
    # `yield` written inside a block reaches. The struct is cells, n_cells,
    # lexical_blk, binding.
    PROC_ENV_LEXICAL_BLK = 16
    # `zeo_rt_runtime_set_visibility`'s verb, which is the runtime's
    # `mark_visibility_rows` scale.
    VISIBILITY_VERBS = { "private" => 0, "protected" => 1, "public" => 2 }.freeze
    # `zeo_abi::abi::FOR_STATE_SIZE`: the `for` driver's state, which
    # lives in one stack slot for the length of the loop.
    FOR_STATE_BYTES = 96
    # `zeo_rt_last_match_ref`'s kind: which of the `$~` family to read.
    # They all come off the one last-match slot, so `$1` is group 1 and
    # `$&` is group 0.
    LAST_MATCH_DATA = 0
    LAST_MATCH_GROUP = 1
    LAST_MATCH_PRE = 2
    LAST_MATCH_POST = 3
    LAST_MATCH_LAST_GROUP = 4
    # `zeo_rt_eval_reflect_dispatch`'s entry: which of the four names
    # that pick a method at RUN time the site wrote.
    REFLECT_SEND = 0
    REFLECT_PUBLIC_SEND = 1
    REFLECT_RESPOND_TO = 2
    REFLECT_METHOD = 3
    # `zeo_abi::abi::SignalKind`: the jump a value is travelling as. A
    # jump arms one whenever it cannot reach its target directly -- out of
    # a block, or across an `ensure` that owes its clause a run.
    SIGNAL_BREAK = 1
    SIGNAL_NEXT = 2
    SIGNAL_REDO = 3
    SIGNAL_RETURN = 5
    SIGNAL_RAISE = 6
  end
end
