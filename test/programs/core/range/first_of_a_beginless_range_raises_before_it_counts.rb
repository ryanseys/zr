# range_first: a beginless range raises RangeError before the count of
# arguments is read; any other range then takes one count.
def show
  p yield
rescue RangeError, ArgumentError, TypeError => e
  p [e.class, e.message]
end

show { (..5).first }
show { (..5).first(1) }
show { (..5).first(1, 2) }
show { (..5).first(1, 2, 3) }
show { (1..5).first(1, 2) }
show { (1..5).first(1, 2, 3) }
show { (1..5).first }
show { (1..5).first(2) }
show { (1..).first(3) }
show { (1..5).first(0) }
show { (1..5).first(-1) }
show { (1..5).first(nil) }
show { ("a".."e").first(2.9) }
show { (1...1).first(2) }
