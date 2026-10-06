# An `alias`/`alias_method` whose source is defined neither in this body
# nor anywhere in the ancestry COMPILES (the compiler can't distinguish a
# typo from a runtime-table builtin source, `alias_method :dup!, :dup`)
# and raises `NameError` at program start instead -- real Ruby's timing,
# the class body executing. The full-message shape is asserted in the
# "alias whose source resolves nowhere is a name error at program
# start" test.

class Foo
  alias bar undefined_method
end
