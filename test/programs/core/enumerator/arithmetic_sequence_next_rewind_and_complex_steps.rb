# An arithmetic sequence's next stops with StopIteration and starts over
# after rewind; a Complex step walks from a Real start; and wrong counts
# of arguments report CRuby's arity.
def show
  p yield
rescue StandardError => e
  p [e.class, e.message]
end

seq = 1.step(2, 2)
show { seq.next }
show { seq.next }
show { seq.next }
seq.rewind
show { seq.next }
show { seq.next }

seq = 10.step(5, -2)
show { [seq.next, seq.next] }
seq.rewind
show { [seq.next, seq.next, seq.next] }
show { seq.next }

show { (1..).step(1i).take(3) }
show { (1..).step(1.0i).take(3) }
show { (0.0..).step(1.0i).take(3) }
show { (0.0i..).step(1.0i).take(3) }

show { SignalException.new(1, "", nil) }
show { Hash.new(1) {} }
show { Module.send(:define_method, 1, 2, 3) }
show { "".sub!(//) }
show { "".sub! {} }
