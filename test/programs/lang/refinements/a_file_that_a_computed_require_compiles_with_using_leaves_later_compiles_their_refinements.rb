# A file that a require with a computed name compiles at run time takes
# `using` entries after every entry in use. So the program's own
# refinements, and the parser that compiles the next eval or file, still
# find theirs after the file's `using` runs.
module Own
  refine Integer do
    def own_ref = :own
  end
end
using Own

$LOAD_PATH.unshift File.expand_path("lib")
feature = "runtime_using"
require feature
p 2.own_ref
def later = 3.own_ref
p later
p eval("foo = 4; bar rescue foo")
p eval("[5, 6].sum { |x| x * 2 }")
p((7.runtime_dclone rescue $!.class))
