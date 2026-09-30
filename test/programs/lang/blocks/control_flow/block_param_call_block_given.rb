# A method that captures its block as `&blk` AND calls `block_given?`
# calls the block through `blk.call`. `block_given?` does not change
# how the literal block reaches `blk`.

# 1. Top-level &blk + block_given? + blk.call.
def build(&blk)
  blk.call(42) if block_given?
end
build { |x| puts x }              #=> 42

# 2. Expression context: the call result is consumed.
def build_v(&blk)
  r = blk.call(21) if block_given?
  r
end
puts build_v { |x| x * 2 }        #=> 42

# 3. Instance method.
class Foo
  def run(&blk)
    blk.call(7) if block_given?
  end
end
Foo.new.run { |x| puts x }        #=> 7

# 4. Singleton (class) method.
class Bar
  def self.make(&blk)
    blk.call(9) if block_given?
  end
end
Bar.make { |x| puts x }           #=> 9

# 5. A method mixing &blk and an actual yield still works.
def mix(&blk)
  yield 5 if block_given?
end
mix { |x| puts x }                #=> 5

puts "done"
