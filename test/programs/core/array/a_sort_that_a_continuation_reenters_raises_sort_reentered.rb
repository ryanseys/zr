# A continuation that a sort's block took can enter a comparison again
# after the sort returned: that comparison raises RuntimeError "sort
# reentered", as sort_reentered checks. A sort that a block leaves with
# break returns the break's value and leaves the Array as it was.
verbose, $VERBOSE = $VERBOSE, nil
require "continuation"
$VERBOSE = verbose
def reenter(sorter)
  n = 3
  cont = nil
  ary = (1..10).to_a
  e = nil
  begin
    result = ary.public_send(sorter) do |a, b|
      callcc { |k| cont = k } unless cont
      a <=> b
    end
  rescue => e
  end
  n -= 1
  cont.call if n.positive?
  [e.class, e&.message, ary.frozen?, result&.frozen?]
end
p reenter(:sort!), reenter(:sort)
a = [3, 1, 2]
p a.sort! { |x, y| x <=> y }, a.frozen?
p a.sort { |x, y| y <=> x }.frozen?
p([3, 1, 2].sort { |x, y| break :out })
b = [2, 1]
p b.sort! { |x, y| break :gone }, b, b.frozen?
