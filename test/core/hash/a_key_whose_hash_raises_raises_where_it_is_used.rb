# A key's own `hash` or `eql?` that raises raises at the call that ran
# it, and a key's `eql?` that grows the table under a lookup leaves the
# table whole.
class Bad
  def hash = raise("boom")
end

identity = {}.compare_by_identity
identity[Bad.new] = 1

begin
  {**identity}
rescue => e
  p [:splat, e.message]
end

begin
  {}.update(identity)
rescue => e
  p [:update, e.message]
end

begin
  {Bad.new => 1}
rescue => e
  p [:literal, e.message]
end

begin
  {a: 1}[Bad.new]
rescue => e
  p [:aref, e.message]
end

begin
  {a: 1}.fetch(Bad.new)
rescue => e
  p [:fetch, e.message]
end

begin
  {a: 1}.key?(Bad.new)
rescue => e
  p [:key?, e.message]
end

class Later
  def hash = $late ? raise("late") : 1
end
kept = {Later.new => 1}
$late = true
begin
  kept.rehash
rescue => e
  p [:rehash, e.message]
end

after = {}
after[:a] = 1
p after

H = {}
class Grow
  def hash = 1
  def eql?(other) = (20.times { |i| H[i] = i }; true)
end
H[Grow.new] = 1
H[Grow.new] = 2
p H.size

__END__
[:splat, "boom"]
[:update, "boom"]
[:literal, "boom"]
[:aref, "boom"]
[:fetch, "boom"]
[:key?, "boom"]
[:rehash, "late"]
{a: 1}
21
