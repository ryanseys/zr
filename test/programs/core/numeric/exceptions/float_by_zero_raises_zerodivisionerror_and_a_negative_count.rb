# Float#% by zero raises ZeroDivisionError (not NaN); a negative first/last
# count raises ArgumentError with the receiver-specific message.

def t; yield; rescue => e; "#{e.class}: #{e.message}"; end
p t { 5.0 % 0 }
p t { 5.0 % 0.0 }
p 5.0 % 2
p(-5.5 % 2)
p t { [1, 2, 3].first(-1) }
p t { [1, 2, 3].last(-2) }
p t { (1..3).first(-1) }
p t { [1, 2, 3].cycle.first(-1) }
p [1, 2, 3].first(2)
