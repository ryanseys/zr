# The message of a NoMatchingPatternError is made as compile.c makes it:
# after several patterns, the subject itself, which Exception#to_s
# converts; after one, core#sprintf's "%p: %s". Neither is a send from
# the program's scope, so a refinement of to_s or inspect does not change
# it. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

class Shown
  def to_s = "S"
  def inspect = "I"
end

module ToS
  refine Integer do
    def to_s = "refined to_s"
  end
end

module Inspect
  refine Integer do
    def inspect = "refined inspect"
  end
  refine Array do
    def inspect = "refined array"
  end
  refine Symbol do
    def inspect = "refined symbol"
  end
end

using ToS
using Inspect

try("two patterns") { case 0; in nil; in 1; end }
try("one pattern") { case 5; in nil; end }
try("=>") { 5 => String }
try("array length") { case [0, 1]; in [nil]; end }
try("array element") { case [0]; in [String]; end }
try("find pattern") { case [1, 2]; in [*, 9, *]; end }
try("hash value") { case({ a: 0 }); in { a: nil }; end }
try("hash missing key") { case({ a: 1 }); in { b: }; end }
try("hash rest") { case({ a: 1, b: 2 }); in { a:, **nil }; end }
try("no deconstruct") { case 3; in [x]; end }
try("nil subject") { case nil; in 1; in 2; end }
try("class subject") { case Object; in 1; in 2; end }
try("own to_s") { case Shown.new; in 1; in 2; end }
try("own inspect") { case Shown.new; in 1; end }
try("key error key") do
  case({ a: 1 })
  in { b: }
  end
rescue NoMatchingPatternKeyError => e
  [e.key, e.matchee]
end
# The program's own sends still see the refinements.
p 0.to_s, 5.inspect, [1].inspect, "#{0}"
