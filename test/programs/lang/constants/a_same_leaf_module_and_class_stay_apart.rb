# Two namespaces may each hold a constant of the same LEAF name, and neither
# may answer for the other. One row per shape, printed as `name<TAB>result`.
#
# zr decides at LOWERING time whether a `class X < Super` is a compile-time
# class or a runtime `X = Class.new(Super)`, and that decision reads two
# whole-program tables: "is this constant assigned?" and "is this constant a
# class definition?". The second always asked from the CREF the site is
# written in; the first asked by BARE LEAF, over the whole program.
#
# So one namespace's `Path = Struct.new(...) do ... end` made every `class X <
# Path` anywhere look like a subclass of a runtime-minted class, and a plain
# `class Path` in another namespace was rewritten into a runtime REOPEN of a
# class that does not exist there -- `uninitialized constant Files::Path`,
# four lines into this file, for ordinary Ruby.
#
# Under `require "bundler"` the same collision was quieter and worse:
# `Bundler::Settings::Path` rewrote `class Git < Path` in
# `bundler/source/git.rb` to `Git = Class.new(Path)`, so
# `Bundler::Source::Git` existed TWICE -- once as a compile-time class
# nothing ever revealed, once as the runtime class in the constant table.
# `const_get(:Git)` answered the second and `Bundler::Source::Git` raised on
# the first.
#
# The fix is one rule: a scope-less write is keyed by its cref path, and the
# query is Ruby's own lexical search -- exactly what `record_class_def` and
# `class_defined_in_scope` already did for the class half. Two hand-rolled
# leaf-matching workarounds went away with it.
#
# Every row below is ordinary Ruby with an unambiguous answer.

def row(name)
  print name, "\t"
  begin
    puts(yield.inspect)
  rescue Exception => e
    puts "#{e.class}: #{e.message}"
  end
end

# --- 10. a same-leaf module and class ---------------------------------------

module KindA
  Mixed = Module.new
end
module KindB
  class Mixed; end
  class UsesMixed < Mixed; end
end

row("kinda_mixed_class") { KindA::Mixed.class.to_s }
row("kindb_mixed_class") { KindB::Mixed.class.to_s }
row("kindb_uses_superclass") { KindB::UsesMixed.superclass.to_s }
