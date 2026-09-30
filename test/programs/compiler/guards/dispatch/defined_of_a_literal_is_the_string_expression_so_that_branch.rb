# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# `defined?` of a LITERAL is the string "expression", so the branch always
# runs. faraday-stack's `if defined?("Faraday::Env")` means this, whatever
# its author had in mind.
if defined?("Faraday::Env")
  module Patch
    APPLIED = true
  end
end
p Patch::APPLIED

