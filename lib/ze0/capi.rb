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
      "zeo_rt_int_add_slow" => [%w[i64 i64 i64], nil],
      "zeo_rt_int_sub_slow" => [%w[i64 i64 i64], nil],
      "zeo_rt_int_mul_slow" => [%w[i64 i64 i64], nil],
      "zeo_rt_wrong_arity" => [%w[i64 i64 i64], "i32"],
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
  end
end
