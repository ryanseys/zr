require "stringio"

# A pattern's ===, the block, or an element's own truth: rb_ary_any_p
# and its three kin count the elements that meet the criterion, and
# they read one optional pattern, not a list of them.
p [1, 2].all?(Integer)
p [1, 2].none?(String)
p [1, 2].one?(1)
p [nil].any?(nil)
p [nil, false].any?
p [nil, false].none?
p [].any?
p [].all?
p [].one?
p [1, 2, 3].one? { |x| x > 2 }
p [1, 2, 3].one? { |x| x > 1 }
p [1, 2].all? { |x| x > 0 }
p [1, 2].any?(&:even?)
p [[1, 2]].any? { |a, b| b == 2 }

# A second pattern is refused, in the words rb_ary_any_p refuses it.
[:any?, :all?, :none?, :one?].each do |name|
  [1, 2].public_send(name, 1, 2)
rescue ArgumentError => e
  puts "#{name}: #{e.message}"
end

# A pattern and a block together: the pattern answers, and the
# block is said to be unused.
saved = $stderr
$stderr = StringIO.new
p [1, 2, 3].any?(2) { |x| x > 5 }
said = $stderr.string
$stderr = saved
said.each_line { |line| puts line.split(": ", 2).last }

# A break leaves the question carrying its own value, through the
# block the question reaches the caller's block with.
p([1, 2, 3].none? { |x| break :out })

# The block is called with the one element, so a lambda's arity
# must fit it.
begin
  [[1, 2]].all?(&->(a, b) { true })
rescue ArgumentError => e
  puts e.message
end

# The walk is by index, as rb_ary_any_p's is, so a subclass that
# writes its own `each` is not asked.
class Odd < Array
  def each
    return to_enum(:each) unless block_given?

    yield 9
    self
  end
end
p Odd.new([1, 2]).any? { |x| x == 9 }
