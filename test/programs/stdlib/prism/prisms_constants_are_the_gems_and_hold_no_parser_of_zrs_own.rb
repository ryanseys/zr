# prism's C extension has its parser in C: Prism holds the gem's names
# and none of zr's Ruby port of that parser.
require "prism"
p Prism.constants.include?(:Ruby), Prism.const_defined?(:Ruby)
p((Prism.const_get("Ruby::Parser") rescue $!.class))
p Prism.parse("1 + 2").value.statements.body.first.class
