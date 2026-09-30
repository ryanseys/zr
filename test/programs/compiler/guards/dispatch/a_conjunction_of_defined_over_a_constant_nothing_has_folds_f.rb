# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# A conjunction of `defined?`s over a constant nothing in the program has:
# the branch never runs.
if defined?(HTTP) && defined?(HTTP::VERSION)
  module Adapter
    NOPE = 1
  end
end
p defined?(Adapter)

