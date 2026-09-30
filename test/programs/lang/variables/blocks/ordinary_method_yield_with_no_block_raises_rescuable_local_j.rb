# An ordinary method that yields with no block raises LocalJumpError, and
# a rescue catches it.

def m
  yield
end
begin
  m
rescue LocalJumpError => e
  puts "caught #{e.class}"
end
puts m { "with-block" }
