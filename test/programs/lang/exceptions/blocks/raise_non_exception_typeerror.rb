# `raise <non-exception>` is CRuby's TypeError. The value does not become
# the message.
def try
  yield
rescue TypeError => e
  puts "TypeError: #{e.message}"
end
try { raise 42 }
try { raise nil }
try { raise [1, 2] }
try { raise :sym }
try { raise 3.5 }
try { raise({ a: 1 }) }
# a string still raises RuntimeError with the message
begin
  raise "boom"
rescue RuntimeError => e
  puts "RuntimeError: #{e.message}"
end
# a runtime-typed (poly) operand dispatches on the value
mixed = [Object.new, "msg"]
begin
  raise mixed[1]
rescue RuntimeError => e
  puts "poly string: #{e.message}"
end
begin
  raise mixed[0]
rescue TypeError => e
  puts "poly object: #{e.message}"
end
puts "after"
