# Ripper over prism: sexp and sexp_raw, the tokens lex and tokenize
# answer, slice, a Filter, a subclass's own events with the position each
# one stands at, and the errors a broken program reports.
require "ripper"
require "pp"
src = <<~'RB'
  def m(a, b = 1) = a + b
  x = <<~H
    one #{x}
      two
  H
  [1, 2].map { |v| v * 2 } # note
  class Foo < Bar; attr_reader :q; end
  case y
  in [Integer => n, *] then n
  end
  puts "a#{b}c", :sym, 1.5r, ?x
RB
pp Ripper.sexp(src)
pp Ripper.sexp_raw("a.b(1)")
pp Ripper.lex(src).map { |pos, event, tok, _state| [pos, event, tok] }
p Ripper.tokenize("def m(a) nil end")
p Ripper.slice("def m(a) nil end", "ident")
p Ripper.sexp("def (")
p Ripper.lex("def (").map { |pos, event, tok, _state| [pos, event, tok] }
class Counter < Ripper::Filter
  def on_default(event, tok, data) = data.merge(event => data.fetch(event, 0) + 1)
end
p Counter.new("a = 1 + b").parse({})
r = Ripper.new("foo(1)")
p [r.lineno, r.column, r.filename]
class Show < Ripper
  def on_int(t) = [:int, t, lineno, column, state]
  def on_method_add_arg(c, a) = [:mad, c, a]
end
p Show.new("foo(1)").parse
p Ripper.dedent_string(+"    hello", 2)
p Ripper.lex_state_name(Ripper::EXPR_BEG | Ripper::EXPR_LABEL)
begin
  Ripper.sexp("def (", raise_errors: true)
rescue SyntaxError => e
  p e.class
end

