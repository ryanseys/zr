def t; yield; rescue NoMatchingPatternError => e; p [e.class, e.message, (e.key rescue nil), (e.matchee rescue nil)]; end
t { 1 => String }
t { {a: 1} => {b:} }
t { {a: 1} => {a: String} }
t { [1] => [a, b] }
t { case 5; in String then 1; end }
t { case [1,2]; in [x] then 1; end }
t { 1 => Integer => x; p x }
t { {a: 1} => {a:}; p a }
t { [1, [2, 3]] => [_, [*, y]]; p y }
t { 1 in String }
r1 = (1 in Integer); r2 = ({a: {b: 1}} in {a: {b: Integer => q}}); p r1, r2, q
t { 5 => ^(2+3) }
t { {a: 1, b: 2} => {a:, **rest}; p rest }
t { {a: 1} => {a:, **nil} }
t { {a: 1, b: 2} => {a:, **nil} }
t { [1,2,3,4] => [*, 2, x, *post]; p x, post }
t { 3 => 1.. | 5.. }
t { nil => nil }
t { {} => {} }
t { {a: 1} => {} }
t { [] => [] }
t { "x" => String | Symbol => s; p s }
class Pt; def deconstruct = [1,2]; def deconstruct_keys(k) = (p k; {x: 1, y: 2}); def inspect = "#<Pt>"; end
t { Pt.new => [a, b]; p [a,b] }
t { Pt.new => {x:, y:}; }
t { Pt.new => {x:, **r}; }
t { Pt.new => Pt(x:) }
t { Pt.new => Pt[1, 2] }
t { Pt.new => Pt[1] }
t { case 1; in Integer if false then p :a; in x unless false then p [:b, x]; end }
class Plain; def inspect = "#<Plain>"; end
t { Plain.new => [a] }
class Bad; def deconstruct = 1; end
t { begin; Bad.new => [a]; rescue TypeError => e; p e; end }
class BadK; def deconstruct_keys(k) = 1; end
t { begin; BadK.new => {a:}; rescue TypeError => e; p e; end }
t { {a: 1, b: 2} => {a: Integer => n, b: 2 => m}; p n, m }
t { [1, "a", :b] => [Integer, String, Symbol] }
t { 1 => 1 | 2 }
t { {name: "x", age: 3} => {name: String => nm}; p nm }
t { [1, [2, [3]]] => [a, [b, [c]]]; p [a, b, c] }
t { {a: nil} => {a: nil} }
t { {a: 1} => {a: nil} }
t { [1, 2] => [*x]; p x }
t { [1, 2, 3] => [1, *x, 3]; p x }
t { {x: 1} => {x: 1 => v}; p v }
t { [1, 2] => [Integer, Integer] => pair; p pair }
t { 5 => Integer | Float => num; p num }
t { x = 5; 5 => ^x }
t { x = 5; 6 => ^x }
t { 6 => ^@iv rescue p $! }
t { [1, 2] => [a, *] }
t { [[1, 2], [3, 4]] => [[*, 2], [3, *]] }
t { {a: {b: {c: 1}}} => {a: {b: {c:}}}; p c }
p(case [1, 2]; in [a, b] if a < b then :ordered; in [a, b] then :not; end)
p(case {status: "ok", data: [1]}; in {status: "ok", data: [first, *]} then first; end)
p(case 3; in Integer | Float => n then n * 2; end)
t { 1 => _ }
t { [1, 2] => [_, _] }
t { [1] => [_, _] }
t { "str" => /s(t)r/; p $~ }
t { 1 => ->(x) { x > 0 } }
t { [1, 2] => Array(a, b); p [a, b] }
t { {} => {a: 1} }
t { {a: 1} => {a: 1, **nil} }
t { {a: 1} => {b: 1, **rest} }
Point = Struct.new(:x, :y)
t { Point.new(1, 2) => Point[x:, y:]; p [x, y] }
t { Point.new(1, 2) => [x, y]; p [x, y] }
t { Point.new(1, 2) => {x:}; p x }
D = Data.define(:w, :h)
t { D.new(w: 1, h: 2) => {w:, h:}; p [w, h] }
t { D.new(w: 1, h: 2) => D[w:]; p w }
t { case 1; in 0 then p :zero; else p :other; end }
t { case [1, 2, 3]; in [Integer => a, *rest] then p [a, rest]; end }
t { case {k: 1}; in {k: Integer} | {j: String} then p :alt; end }
t { case 1; in ..0 then p :neg; in 1.. then p :pos; end }
t { [1, 2, 3, 4, 5] => [first, *, last]; p [first, last] }
t { case "a"; in "a" | "b" then p :ab; end }
t { case :s; in :s then p :sym; end }
t { {a: 1} => {a: 1 | 2 => z}; p z }
t { case {a: 1}; in {a: Integer => v} if v > 5 then p :big; in {a:} then p [:small, a]; end }
t { case [1, [2]]; in [x, [y]] then p [x, y]; end }
t { case 42; in Integer | Float => n if n > 40 then p n; end }
t { 1 => Integer unless false rescue p $! }
p((1 in Integer | String))
p((nil in nil))
p(([1, 2] in [_, _, _]))
t { case {}; in {} then p :empty; end }
t { case {a: 1}; in {} then p :empty; in {a:} then p :nonempty; end }
t { case []; in [] then p :emptyarr; end }
t { case [1]; in [] then p :emptyarr; in [x] then p x; end }
t { [1, 2] => [Integer => i, ^i] rescue p $! }
t { [1, 1] => [Integer => i, ^i]; p i }
t { case 5; in n if n.odd? then p :odd; end }
t { {a: 1} => {a: 1} => whole; p whole }
t { case [1, 2]; in [1, *] | [*, 2] then p :either; end }
t { case 5; in String then 1; in Symbol then 2; end }
t { 5 => Integer if false }
t { case 5; in Integer if false then 1; end }
t { case 5; in Integer unless true then 1; end }
t { [1, 2, 3] => [*, 9, *] }
t { 5 => String | Symbol }
t { [1, 2] => [_, _, *] }
t { [1] => [_, _, *] }
t { 1 => [] }
t { 1 => {} }
t { {a: 1} => {a: String} | {a: Symbol} }
t { {a: 1} => [] }
t { [1] => {} }
t { 5 => nil }
t { {a: {b: 1}} => {a: {b: String}} }
t { {a: {b: 1}} => {a: {c:}} }
t { [[1]] => [[String]] }
t { Struct.new(:a).new(1) => {b:} }
t { 5 => ^(1..3) }
class Pt2; def deconstruct_keys(k) = {}; def inspect = "#<Pt2>"; end
t { Pt2.new => {a:} }
t { {a: 1}.freeze => {a: 1, **rest}; p rest, rest.frozen? }
t { {a: 1} => {a:, **rest}; p rest }
x = 1
t { [2] => [^x] }
t { [x] => [^x] }
t { {"k" => 1} => {} }
t { :sym => String }
t { 1.5 => Integer }
t { "str" => "str" }
t { [] => [*a]; p a }
t { [1, [2, 3]] => [Integer => a, [*rest]]; p a, rest }
case [1, 2]
in [Integer, Integer] => pair
  p pair
end
in_result = ([1, 2] in [Integer, Integer])
p in_result
p((5 in Integer => y), y)
v = {name: "n"}
if v in {name: String => name}
  p name
end
t { 5 => x }
p x
h = {a: 1}
t { h => {a:}; p a }
t { case {a: 1}; in {a: 1 => b} then p b; end }
p(case 1; in Integer; :int; end)
case 1
in Integer then p :int1
end
def deconstruct_calls
  o = Object.new
  def o.deconstruct = (puts "deconstruct"; [1, 2])
  def o.deconstruct_keys(k) = (puts "keys #{k.inspect}"; {a: 1})
  def o.inspect = "#<o>"
  o
end
t { deconstruct_calls => [a, b] }
t { deconstruct_calls => [_, _] | [_] }
t { deconstruct_calls => {a:} }
t { deconstruct_calls => {a:, **rest} }
t { deconstruct_calls => {a:, b:} }
t { deconstruct_calls => {a: 1} | {a: 2} }
t { deconstruct_calls => [*, 2, *] }
t { 1 => Integer | String => z; p z }
t { [1, 2] => [_] | [_, _] }
t { {a: 1, b: 2} => {a: 1} | {b: 2}; }
t { case 1; in Integer | Float => n if n.zero? then p :z; in n then p [:n, n]; end }
t { 1 => (Integer | String) => q; p q }
t { [1, 2, 3] => [1, *rest] => whole; p rest, whole }
t { {a: 1} => {a: Integer => one} => whole; p one, whole }
p defined?(NoMatchingPatternKeyError), NoMatchingPatternKeyError.superclass, NoMatchingPatternError.superclass
begin
  {a: 1} => {b:}
rescue NoMatchingPatternKeyError => e
  p e.key, e.matchee, e.message
end
begin
  raise NoMatchingPatternKeyError.new("m", matchee: 1, key: 2)
rescue => e
  p e.message, e.key, e.matchee
end
p NoMatchingPatternKeyError.new("m").message, (NoMatchingPatternKeyError.new("m").key rescue $!.class)
if /(?<year>\d+)-(?<mon>\d+)/ =~ "2024-05"
  p [year, mon]
end
p(/(?<nope>z)/ =~ "abc", nope)
3.times do |i|
  o = Object.new
  def o.deconstruct = (puts "deconstruct"; [1, 2])
  case o
  in [a, b] then p [i, a, b]
  end
end
[[1, 2], [3]].each do |arr|
  case arr
  in [x, y] then p [:two, x, y]
  in [x] then p [:one, x]
  end
end
def m(v)
  case v
  in Integer | Float => n then [:num, n]
  in String => s if s.size > 2 then [:long, s]
  in String then [:short]
  in [] then [:empty]
  in [first, *] then [:first, first]
  in {type: :circle, r:} then [:circle, r]
  in nil then [:nil]
  end
end
p m(1), m(2.5), m("abcd"), m("a"), m([]), m([9, 8]), m({type: :circle, r: 2}), m(nil)
p((begin; m(:sym); rescue NoMatchingPatternError => e; e.message; end))
