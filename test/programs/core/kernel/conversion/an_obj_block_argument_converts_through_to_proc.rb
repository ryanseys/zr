# Ruby's implicit-conversion protocols: `&obj` converts through `to_proc`,
# `**obj` through `to_hash`, and a splice/auto-splat value through `to_ary`.
# Each is duck-typed -- any object answering the method participates.

# --- &obj -> to_proc -------------------------------------------------------

# A Symbol is the familiar case.
p [1, 2, 3].map(&:to_s)
p %w[a b].map(&:upcase)

# A Proc passes straight through.
doubler = ->(x) { x * 2 }
p [1, 2, 3].map(&doubler)

# A Method object converts via Method#to_proc.
def triple(x) = x * 3
p [1, 2, 3].map(&method(:triple))

# Any object defining to_proc converts.
class Dbl
  def to_proc
    ->(x) { x * 2 }
  end
end
p [1, 2, 3].map(&Dbl.new)
d = Dbl.new
p [10, 20].map(&d)

# nil means "no block at all".
def block_given_here(&blk)
  blk.nil?
end
p block_given_here(&nil)

# An object whose to_proc answers a non-Proc is a TypeError.
class BadProc
  def to_proc = :not_a_proc
end
begin
  [1].map(&BadProc.new)
rescue TypeError => e
  puts "TypeError: #{e.message}"
end

# An object with no to_proc at all is a TypeError.
class NoProc; end
begin
  [1].map(&NoProc.new)
rescue TypeError => e
  puts "TypeError: #{e.message}"
end

