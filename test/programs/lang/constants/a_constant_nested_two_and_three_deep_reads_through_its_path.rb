# ConstantPath access — covers ARGV (top-level builtin), built-in
# constructors (::Array.new etc.), nested const reads (A::B::C),
# class-method dispatch (A::B.create), and the relative-vs-root
# scope distinction (RootNS::Mid::LEAF vs ::RootNS::Mid::LEAF).
# Merged from constant_path_{argv,builtin_new,class_method,
# nested_read,new}.rb. The class-method section's `A::B` (a class)
# would collide with the nested-read section's `A::B::C` (where
# A::B is a module), so the class-method section is namespaced as
# CmA::CmB to keep both shapes co-resident.

# ---- Nested ConstantPath reads (A::B::C, M::C::X) ----
module A
  module B
    C = 7
  end
end
module M
  class C
    X = 11
  end
end
puts A::B::C
puts ::A::B::C
puts M::C::X
puts ::M::C::X

# Relative path prefers lexical scope; `::` forces root scope.
module RootNS
  module Mid
    LEAF = 31
  end
end
module Lex
  module RootNS
    module Mid
      LEAF = 47
    end
  end
  def self.pick_relative
    RootNS::Mid::LEAF
  end
  def self.pick_root
    ::RootNS::Mid::LEAF
  end
end
puts Lex.pick_relative
puts Lex.pick_root

