# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# A `const_set` that pins down NEITHER the constant it names nor the module it
# sets it on is evidence about no constant in particular. webmock's
# `@webMockNetHTTP.const_set(c[0], c[1])` is one of these, and reading it as a
# possible `HTTP::VERSION` left every scoped guard below it undecidable.
class Registry; end
into = Registry
[["Alpha", 1]].each { |pair| into.const_set(pair[0], pair[1]) }
p Registry::Alpha

module HTTP; end
if defined?(HTTP::VERSION)
  module Versioned
    NOPE = 1
  end
end
p defined?(Versioned)

