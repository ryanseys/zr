# CRuby's rb_equal: an element inside a container is equal to itself
# before `==` is asked, which is what makes `[nan].include?(nan)` true
# while `nan == nan` is false.
n = Float::NAN
p [n == n, [n] == [n], { a: n } == { a: n }]
p [[n].rindex(n), [n].count(n), [n].delete(n)]
p [[[n, 1]].assoc(n), [[1, n]].rassoc(n)]
p [{ a: n }.value?(n), { a: n }.key(n), { a: n }.rassoc(n), { a: n } <= { a: n }]
p [[n].each_entry.include?(n), [n].each_entry.count(n), [n].each_entry.find_index(n)]

# A user `==` that answers false for its own receiver loses the same way.
class Never
  def ==(_other) = false
  def inspect = "Never"
end
q = Never.new
p [q == q, [q] == [q], [q].include?(q), [q].index(q), [q].rindex(q), [q].count(q)]
p({ a: q } == { a: q })
__END__
[false, true, true]
[0, 1, NaN]
[[NaN, 1], [1, NaN]]
[true, :a, [:a, NaN], true]
[true, 1, 0]
[false, true, true, 0, 0, 1]
true
