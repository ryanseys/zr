# `x ||= v` is `x || (x = v)` and `x &&= v` is `x && (x = v)`: the write
# happens only when the value is needed. A frozen receiver sees that --
# memoizing into an ivar that is already set does not write -- and so does
# a constant's redefinition warning.
class Memo
  def initialize = (@x = 1; @y = nil)
  def or_x = (@x ||= 2)
  def and_y = (@y &&= 3)
  def or_y = (@y ||= 4)
end
memo = Memo.new.freeze
p memo.or_x
p memo.and_y
begin
  memo.or_y
rescue FrozenError => e
  p e.class
end

$g = 5
p($g ||= 6, $g &&= 7, $g)
$n = nil
p($n &&= 1, $n ||= 2, $n)

class Counter
  @@v = nil
  p(@@v &&= 1, @@v ||= 2, @@v &&= 3, @@v)
end

K = 1
p(K &&= K)
module Holder
  X = nil
end
p(Holder::X &&= 2)
p(Holder::X ||= 3)

__END__
1
nil
FrozenError
5
7
7
nil
2
2
nil
2
3
3
1
nil
3
#@ stderr
lang/variables/an_or_assignment_writes_only_when_it_has_to.rb:31: warning: already initialized constant K
lang/variables/an_or_assignment_writes_only_when_it_has_to.rb:30: warning: previous definition of K was here
lang/variables/an_or_assignment_writes_only_when_it_has_to.rb:36: warning: already initialized constant Holder::X
lang/variables/an_or_assignment_writes_only_when_it_has_to.rb:33: warning: previous definition of X was here
