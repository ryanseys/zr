# ConstantPath access — covers ARGV (top-level builtin), built-in
# constructors (::Array.new etc.), nested const reads (A::B::C),
# class-method dispatch (A::B.create), and the relative-vs-root
# scope distinction (RootNS::Mid::LEAF vs ::RootNS::Mid::LEAF).
# Merged from constant_path_{argv,builtin_new,class_method,
# nested_read,new}.rb. The class-method section's `A::B` (a class)
# would collide with the nested-read section's `A::B::C` (where
# A::B is a module), so the class-method section is namespaced as
# CmA::CmB to keep both shapes co-resident.

# ---- ConstantPath class-method dispatch (A::B.create) ----
module CmA
  class CmB
    def self.create(x)
      x + 1
    end
  end
end
puts CmA::CmB.create(41)
puts ::CmA::CmB.create(99)

