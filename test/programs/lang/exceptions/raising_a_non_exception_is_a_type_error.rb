# `raise <non-exception>` coerces at runtime -- a String becomes a
# RuntimeError, everything else raises CRuby's TypeError.

def try
  yield
rescue TypeError => e
  puts "TypeError: #{e.message}"
end
try { raise 42 }
try { raise nil }
try { raise :sym }
begin
  raise "boom"
rescue RuntimeError => e
  puts "RuntimeError: #{e.message}"
end
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
