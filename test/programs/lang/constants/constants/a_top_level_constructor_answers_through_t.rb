# ConstantPath access — covers ARGV (top-level builtin), built-in
# constructors (::Array.new etc.), nested const reads (A::B::C),
# class-method dispatch (A::B.create), and the relative-vs-root
# scope distinction (RootNS::Mid::LEAF vs ::RootNS::Mid::LEAF).
# Merged from constant_path_{argv,builtin_new,class_method,
# nested_read,new}.rb. The class-method section's `A::B` (a class)
# would collide with the nested-read section's `A::B::C` (where
# A::B is a module), so the class-method section is namespaced as
# CmA::CmB to keep both shapes co-resident.

# ---- Top-level constructor via absolute ConstantPath (::TopC.new) ----
# Renamed from `class C` to TopC to keep it distinct from M::C above.
class TopC
  def initialize
    puts "init"
  end
end
puts "start"
::TopC.new
