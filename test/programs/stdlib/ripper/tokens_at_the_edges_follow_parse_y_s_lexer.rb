# Tokens where parse.y's lexer has a rule of its own: a `}` that closes
# nothing ends an embedded expression and keeps the state; the spaces and
# comments after the last newline have the state before that newline; a
# magic comment's name has `_` for `-`; __END__ is one token; and
# `a::C {}` is a command call with no arguments.
require "ripper"

["a( foo, bar: baz }", "p 1 }", "}", "x = { a: 1 } }", '"#{1}" }'].each { |source| p Ripper.lex(source).last }
["1\n\t \t", "def f\n  ", "foo\n  ", "a = 1\n  ", "x\n\n  ", "1 \n  ", "p(\n  ", "class A\n ", "1\n  2 "].each do |source|
  p Ripper.lex(source).last(2).map { |(_, event, text, state)| [event, text, state.to_s] }
end

class Magic < Ripper
  def on_magic_comment(*pair) = (@pairs ||= []) << pair
  def self.of(source) = new(source).tap(&:parse).instance_variable_get(:@pairs)
end
p Magic.of("# -*- bug-5753: ruby-dev:44984 -*-"), Magic.of("# frozen-string-literal: true"), Magic.of("# coding: utf-8")

p Ripper.tokenize("__END__\njunk junk junk"), Ripper.lex("1\n__END__").map { it[1] }, Ripper.lex("__END__").map { it[1] }
p Ripper.sexp("a::C {}"), Ripper.sexp("A::B::C { 1 }"), Ripper.sexp("a::c {}"), Ripper.sexp("a.C {}")
