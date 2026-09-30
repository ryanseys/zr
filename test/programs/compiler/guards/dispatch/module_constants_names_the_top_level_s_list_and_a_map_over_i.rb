# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# `Module.constants` names the same list at the top level, and a `map` that
# only respells each entry still holds the same names -- andand asks
# `Module.constants.map { |c| c.to_s }.include?('BlankSlate')`.
unless Module.constants.map { |c| c.to_s }.include?('BlankSlate')
  class BlankSlate
    def tag = "blank"
  end
end
p BlankSlate.new.tag

if Module.constants.map(&:to_s).include?('String')
  module Stringy
    SEEN = true
  end
end
p Stringy::SEEN

