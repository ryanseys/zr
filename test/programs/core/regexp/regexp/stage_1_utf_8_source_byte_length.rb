# Regex coverage — five stages plus literal-form tests. Each section
# gives its locals names of its own (`re_s1a`, ...).


# A regex source containing multi-byte UTF-8 chars must reach the
# runtime with the correct byte length. This section just verifies
# the binary runs past regex init.
re_s1a = /[₀₁₂₃₄₅₆₇₈₉]+/
re_s1b = /\A→\z/
re_s1c = /[αβγ]/
puts "ok"
