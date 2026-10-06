# ConstantPath access — covers ARGV (top-level builtin), built-in
# constructors (::Array.new etc.), nested const reads (A::B::C),
# class-method dispatch (A::B.create), and the relative-vs-root
# scope distinction (RootNS::Mid::LEAF vs ::RootNS::Mid::LEAF).
# Merged from constant_path_{argv,builtin_new,class_method,
# nested_read,new}.rb. The class-method section's `A::B` (a class)
# would collide with the nested-read section's `A::B::C` (where
# A::B is a module), so the class-method section is namespaced as
# CmA::CmB to keep both shapes co-resident.

# ---- Built-in constructors via absolute ConstantPath ----
require "stringio"

bia = ::Array.new(3, 2)
puts bia[0] + bia[2]

bih = ::Hash.new
bih["k"] = bia[1]
puts bih["k"]

bip = ::Proc.new { |x| x + 1 }
puts bip.call(5)

bis = ::StringIO.new("ab")
puts bis.getc

bif = ::Fiber.new { |x|
  ::Fiber.yield(x + 1)
  x + 2
}
puts bif.resume(4)
puts bif.resume(4)

bicur = ::Fiber.current
puts bicur.alive?

