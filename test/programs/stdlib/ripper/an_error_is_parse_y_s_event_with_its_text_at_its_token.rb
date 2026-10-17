# Ripper reports each error as parse.y does: a lexer's error is a
# compile_error, an error of a token is an event of its own whose second
# argument is that token's value, and the text is parse.y's.
require "ripper"

class Errors < Ripper
  %i[compile_error on_parse_error on_assign_error on_alias_error on_param_error on_class_name_error].each do |event|
    define_method(event) do |message, *token|
      (@errors ||= []) << [event, message, *token]
      message
    end
  end

  def self.first(source) = new(source).tap(&:parse).instance_variable_get(:@errors).first
end

[
  "$%", "$", "@@1", "@@%", "@@", "proc{@1}", "@%", "@", "/", "<<a", "<<\"a\"", "<<'a'", "<<\"",
  "def b; c(&); end", "def b; c(*) end", "def b; c(**) end", "def b; c(k: 1, **) end",
  "self = 1", "nil = 1", "$& = 1", "$1 = 1", "def m\n X = 1\nend",
  "alias $a $1", "def foo(A) end", "def foo($a) end", "def foo(@a) end", "def foo(@@a) end", "proc { |A| }",
  "def req(a?:) end", "class bad; end", "module bad; end", "def foo=() = 42", "def foo.bar=() = 42",
  "yield", "break", "def req(a, a) end", "\ea", "\"\\xU\""
].each { |source| p [source, Errors.first(source)] }

p Ripper.new("1").error?, Ripper.new("1").tap(&:parse).error?, Ripper.new("1 +").tap(&:parse).error?

# The lexer puts an error before the token that it is at, with that
# token's place, text and state.
["def req(a, a) end", "begin; nil = 1; end", "begin; alias $x $1; end",
 "class bad; end", "def req(@a) end", "def req(a?:) end", "<<A.upcase\n"].each do |source|
  lexer = Ripper::Lexer.new(source)
  elems = lexer.scan
  error = lexer.errors.first
  after = elems[elems.index(error) + 1]
  p [source, error.to_a, after.to_a, Ripper.tokenize(source).last]
  begin
    Ripper.tokenize(source, raise_errors: true)
  rescue SyntaxError => e
    p e.message
  end
end
