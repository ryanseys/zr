# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# ...and the same guard once the name IS bound: the branch is skipped.
module Already; end
unless Object.const_defined?('Already')
  module Already
    LATE = :late
  end
end
p defined?(Already::LATE)

unless defined?(Thor)
  class Thor
    def tag = "stub"
  end
end
p Thor.new.tag

