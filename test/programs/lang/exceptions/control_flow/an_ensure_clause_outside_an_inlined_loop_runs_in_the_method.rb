# The ensure clause outside the loop runs in the method's frame: its
# raise and its caller give the method's lines.
def raises
  n = 5
  begin
    2.times { |i| return i if i == 1 }
  ensure
    puts caller(0, 1).first
    raise "in ensure #{n}"
  end
end
begin
  raises
rescue => e
  puts e.message, e.backtrace.first
end
