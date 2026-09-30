# `a[i]` and `a[i] = v` with a fixnum index in range are read and written
# in place at the site; every other case still reaches Array's methods, and
# a redefinition of `[]`, `[]=`, `/` or `%` turns the site back into a call.
a = [10, 20, 30]
p [a[0], a[2], a[3], a[-1], a[-4], a[1.0], a["x"] ? 1 : 0] rescue p $!.class
p [a[0], a[2], a[3], a[-1], a[-4], a[1.0]]
a[1] = 21
a[3] = 40
a[-1] = 41
a[6] = 70
p a
begin
  a[9.5] = 1
rescue TypeError => e
  p e.class
end
f = [1, 2].freeze
begin
  f[0] = 9
rescue FrozenError => e
  p [e.class, e.message]
end
p f[0]
begin
  a[-10] = 1
rescue IndexError => e
  p [e.class, e.message]
end
h = { 1 => :one }
p [h[1], h[2]]
h[2] = :two
p h

p [7 / 2, -7 / 2, 7 / -2, -7 / -2, 0 / 5, 7 % 2, -7 % 2, 7 % -2, -7 % -2, 0 % 5, 5 % 5]
p [(2**61) / 3, (2**61) % 7, -(2**61) / 3, -(2**61) % 7, 4611686018427387903 % 2, 4611686018427387903 / 2]
begin
  7 / 0
rescue ZeroDivisionError => e
  p e.class
end
begin
  7 % 0
rescue ZeroDivisionError => e
  p e.class
end

class Array
  alias_method :old_aref, :[]
  def [](i) = "got #{i}"
  def []=(i, v)
    old_aref(0)
  end
end
b = [5, 6]
p [b[0], b[-1], b[1] = 8, b]
class Integer
  def %(o) = :mod
  def /(o) = :div
end
p [7 % 2, 7 / 2, -7 % 2]

