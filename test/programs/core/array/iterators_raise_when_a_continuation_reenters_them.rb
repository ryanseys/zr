# An iterator that a continuation brings back after it returned raises
# "... reentered", as CRuby's iterators do when their hidden state is gone.
# The load warning names the extension's own file, which differs.
verbose, $VERBOSE = $VERBOSE, nil
require "continuation"
$VERBOSE = verbose

def reenter(name)
  cont = nil
  n = 3
  e = nil
  begin
    yield -> { callcc { |k| cont = k } unless cont }
  rescue => e
  end
  n -= 1
  cont.call if n > 0
  p [name, e.class, e&.message]
end

reenter(:permutation) { |mark| [1, 2, 3].permutation { mark.call } }
reenter(:combination) { |mark| [1, 2, 3].combination(2) { mark.call } }
reenter(:repeated_permutation) { |mark| [1, 2, 3].repeated_permutation(2) { mark.call } }
reenter(:repeated_combination) { |mark| [1, 2, 3].repeated_combination(2) { mark.call } }
reenter(:product) { |mark| [1, 2].product([3, 4]) { mark.call } }

o = Object.new
def o.to_ary = callcc { |k| @cont = k; [1, 2, 3] }
e = nil
begin
  p [10, 20, o, 30, o, 40].flatten
rescue => e
else
  o.instance_eval { @cont }.call
end
p [e.class, e.message]

p [1, 2].product([3, 4])
p [1, 2, 3].permutation(2).to_a.size
