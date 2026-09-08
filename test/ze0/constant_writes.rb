# frozen_string_literal: true

# The operator writes a constant takes. `||=` is the one read that
# tolerates an unassigned name; the other two ask for it outright.

FIRST = 1
FIRST_TWICE = FIRST + 1
p FIRST_TWICE

MAYBE ||= 5
p MAYBE

EMPTY = nil
EMPTY ||= 7
p EMPTY

BOTH = 3
BOTH &&= BOTH * 2
p BOTH

module Holder
  COUNT = 1
end

Holder::COUNT += 1
p Holder::COUNT

Holder::EXTRA ||= 9
p Holder::EXTRA

Holder::COUNT &&= 100
p Holder::COUNT

# A pattern in parentheses is the pattern inside, and an `[a,]` trailing
# comma opens the length without binding anything.
def kind(v)
  case v
  in (Integer | Float) then :number
  in [only,] then [:first, only]
  else :other
  end
end

p kind(1), kind(2.5), kind([1, 2, 3]), kind("x")
[1, 2, 3] => [head,]
p head
__END__
2
5
7
6
2
9
100
:number
:number
[:first, 1]
:other
1
#@ stderr
ze0/constant_writes.rb:14: warning: already initialized constant EMPTY
ze0/constant_writes.rb:13: warning: previous definition of EMPTY was here
ze0/constant_writes.rb:18: warning: already initialized constant BOTH
ze0/constant_writes.rb:17: warning: previous definition of BOTH was here
ze0/constant_writes.rb:25: warning: already initialized constant Holder::COUNT
ze0/constant_writes.rb:22: warning: previous definition of COUNT was here
ze0/constant_writes.rb:31: warning: already initialized constant Holder::COUNT
ze0/constant_writes.rb:25: warning: previous definition of COUNT was here
