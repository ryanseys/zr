# The regex engine is C, and a wasm32 module links none. The runtime
# readies it, and the core library compiles a pattern of its own,
# before a program has said whether it wants one: so readying succeeds,
# and compiling answers a handle that stands for a pattern nothing can
# match. A program that matches one stops at `onig_search`, which names
# what is missing. Nothing it compiles gives a warning.
sig [Ptr, I32] => I32
machine def onig_initialize(encodings, count)
  Machine.i32(0)
end

sig [Ptr, Ptr, Ptr, I32, Ptr, Ptr, Ptr] => I32
machine def onig_new(reg, pattern, pattern_end, options, enc, syntax, info)
  Machine.store64(reg, 0, 1)
  Machine.i32(0)
end

sig [Ptr] => Void
machine def onig_free(reg)
end

sig [Ptr, I32] => I32
machine def onig_ze0_take_warnings(buf, len)
  Machine.i32(0)
end
