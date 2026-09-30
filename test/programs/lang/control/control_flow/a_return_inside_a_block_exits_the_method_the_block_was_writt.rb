# A `return` inside a block exits the method the BLOCK was written in, however
# many frames it has to unwind through. Every method it passes on the way is
# just a relay: one that catches a `Signal::Return` of its own -- because it has
# a `begin` or an escaping block -- must still let this one through.
def one
  [1, 2, 3].each { |x| yield x }
  :fell
end
def c1; one { |x| return x }; :no; end
p c1

