# `require` answers true the first time and false every time after -- the
# question is whether the FEATURE loaded, not whether this call site ran.
#
# A resolvable literal require folds to a boolean at compile time. The fold
# sees only a NAME, so it must not answer `true` for each call. A re-require
# of a file is not a first load.
#
# The two spellings must agree with each other as well as with themselves:
# they name one file, so the second one is a re-require whichever came first.

# Statement position, three times.
p require_relative("re_require/dep")
p require_relative("re_require/dep")
p require_relative("re_require/dep")

# A second file's require of the same target is a re-require too.
require_relative "re_require/other"

# Twice inside ONE statement, on a file nothing has loaded yet: the first
# loads, the second does not. The statement's own splice has not happened when
# the fold runs, so both call sites read the loaded set as free.
p [
  require_relative("re_require/pair"),
  require_relative("re_require/pair"),
]

# A runtime call answers from the loaded set, not from a fold.
p [1, 2].map { require_relative("re_require/dep") }

# A builtin feature, whose re-require was already correct.
p require("set")
p require("set")

p DEP
p PAIR
