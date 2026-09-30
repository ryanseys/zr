# `alias_method :foo, :nope_missing`: real Ruby raises NameError when the
# class body EXECUTES (runtime, not compile time) -- mirrored by
# `validate_aliases` at startup, with CRuby's message.

class Typo
  alias_method :foo, :nope_missing
end
puts "unreached"
