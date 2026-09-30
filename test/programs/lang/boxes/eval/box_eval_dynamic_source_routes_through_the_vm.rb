# A NON-literal `box.eval` source (a variable, a computed string) routes
# through the runtime `eval` in the box's dimension -- the same fall-through
# `Kernel#eval` uses for a dynamic source, but carrying `box_id`. A dynamic
# eval reads/calls the box's own (`require`-defined) constants and classes,
# its globals stay isolated from main, and a non-String source raises a
# catchable `TypeError` at runtime rather than a compile error.



require_relative "box_eval/main"
