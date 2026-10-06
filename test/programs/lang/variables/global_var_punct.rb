# Punctuation global variables such as `$!`, `$;`, `$,` and `$/`
# work. `$!` is also used by `rescue => e` bodies.
puts $!.inspect       # nil outside rescue
puts $;.inspect       # nil (split-default sep)
puts $,.inspect       # nil (Array#print sep — same)
puts $/.inspect       # "\n" — the only one with a meaningful default
