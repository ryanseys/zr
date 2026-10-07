# ruby warns for a whole pattern. A literal part of an interpolated
# regexp, alone, can look wrong (`\\]` has a `]` with no escape) where
# the whole pattern is right: there `]` closes the class that `[` opened.
x = "a"
y = /[#{x}\\]/
p y, y.match?("\\"), y.match?("a")
z = eval('/[#{x}\\\\]/')
p z.match?("a")
