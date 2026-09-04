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
      "zeo_rt_pool_mark" => [[], "i64"],
      "zeo_rt_pool_reset" => [%w[i64], nil],
      "zeo_rt_pool_push" => [%w[i64], nil],
      "zeo_rt_retain" => [%w[i64], nil],
      "zeo_rt_release" => [%w[i64], nil],
      "zeo_rt_truthy" => [%w[i64], "i8"],
      "zeo_rt_str_lit_ro" => [["i64", "i64", "i8 uext", "i64"], nil],
      "zeo_rt_kernel_puts" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_send_value_cached" => [%w[i64 i32 i64 i32 i64 i64 i64 i64], "i32"],
      "zeo_rt_send_value_kw_cached" => [%w[i64 i32 i64 i32 i64 i64 i64 i64 i64], "i32"],
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
      "zeo_rt_gvar_get" => [%w[i32 i64 i64 i64], nil],
      "zeo_rt_gvar_assign" => [%w[i32 i64 i64 i64], "i32"],
      "zeo_rt_const_get_cref" => [["i64", "i64", "i64", "i64", "i64", "i64", "i8 uext", "i32", "i64"], "i32"],
      "zeo_rt_const_get_on_value" => [%w[i64 i64 i64 i64 i64 i64], "i32"],
      "zeo_rt_const_set_at" => [%w[i32 i64 i64 i64 i64 i64 i32 i32], nil],
      "zeo_rt_ivar_get_dyn" => [%w[i64 i64 i64 i32 i64], "i32"],
      "zeo_rt_ivar_set_dyn" => [%w[i64 i64 i64 i32 i64], "i32"],
      "zeo_rt_case_eq" => [%w[i64 i64 i64], "i32"],
      "zeo_rt_bind_block_params" => [["i64", "i8 uext", "i64", "i64", "i64", "i64"], "i32"],
      "zeo_rt_bind_params" => [%w[i64 i64 i64 i64 i64], "i32"],
      "zeo_rt_signal_set" => [["i8 uext", "i64"], nil],
      "zeo_rt_signal_kind" => [[], "i8"],
      "zeo_rt_signal_take" => [%w[i64], "i8"],
      "zeo_rt_cell_new" => [%w[i64], "i64"],
      "zeo_rt_cell_load" => [%w[i64 i64], nil],
      "zeo_rt_cell_store" => [%w[i64 i64], nil],
      "zeo_rt_cell_release" => [%w[i64], nil],
      "zeo_rt_yield" => [%w[i64 i64 i64 i64], "i32"],
      "zeo_rt_block_arg_to_proc" => [%w[i64 i64], "i32"],
      "zeo_rt_multi_split" => [["i64", "i64", "i8 uext", "i64", "i64"], "i32"],
      "zeo_rt_regexp_lit" => [
        ["i32", "i64", "i64", "i8 uext", "i8 uext", "i8 uext", "i8 uext", "i64"], "i32",
      ],
      "zeo_rt_proc_new" => [
        %w[i64 i64 i64 i64 i64 i64 i32 i32 i64 i64 i64 i64 i32 i64 i64 i64], nil,
      ],
    }.freeze

    # A value slot: the tag byte, then the payload at +8.
    SLOT_BYTES = 24
    # `zeo_abi`'s tags for the immediates the subset writes; anything at
    # or above HEAP is a refcounted object.
    TAG_NIL = 0
    TAG_BOOL = 1
    TAG_INT = 2
    TAG_FLOAT = 3
    TAG_SYMBOL = 4
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
    # `zeo_abi::abi::SignalKind::Break`: what a `break` out of a block
    # arms and the sending site takes.
    SIGNAL_BREAK = 1
  end
end
