# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# The scope OPERATOR does not reach `Object`'s constants, so asking a real
# namespace for one is nil -- the same rule every other qualified read follows.
module Elsewhere; end
p defined?(Elsewhere::RUBY_ENGINE)
