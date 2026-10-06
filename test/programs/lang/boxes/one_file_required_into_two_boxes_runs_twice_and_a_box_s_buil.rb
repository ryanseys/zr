# Per-box re-execution (the same file `box.require`d into two boxes runs
# twice, with independent class-variable state per box), and per-box
# builtin MONKEYPATCHES: a box's `String#blank?` resolves from that box's
# code while main's `"foo".blank?` stays a NoMethodError -- the docs'
# motivating example, dispatch by DEFINING box.



require_relative "boxes_reexecute/main"
