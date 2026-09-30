# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# `Object.constants.include?` is the same question through the list -- for an
# `Object` receiver its own constants ARE the top-level ones.
if !Object.constants.include?(:Concurrent)
  module Concurrent
    def self.tag = "shim"
  end
end
p Concurrent.tag

module Present; end
if Object.constants.include?(:Present)
  module Present
    SEEN = true
  end
end
p Present::SEEN

