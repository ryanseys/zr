# A String repeated past what memory holds raises NoMemoryError, which a
# program can rescue; uncaught, it prints no line, as ruby's has no
# backtrace.
begin
  "x" * (1 << 60)
rescue NoMemoryError => e
  p [e.class, e.message]
end

def t
  p yield.size
rescue NoMemoryError, ArgumentError => e
  p [e.class, e.message]
end
t { "x".ljust(1 << 60) }
t { Array.new(1 << 60) }
t { String.new(capacity: 1 << 60) }
t { "ab" * (1 << 59) }

"y" * (1 << 61)
