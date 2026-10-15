# The main fiber's kill of itself is no exception: no rescue stops it,
# each ensure runs, at_exit handlers see `$!` as the Integer 2, and the
# program reports the main file and Integer, then exits 1.
$stdout.sync = true
at_exit { p [:at_exit, $!] }

def deep
  yield
ensure
  puts "method ensure"
end

begin
  [1].each do
    deep do
      begin
        Fiber.current.kill
      rescue Exception => e
        p [:rescued, e]
      ensure
        puts "inner ensure"
      end
    end
  end
  puts "not reached"
rescue Exception => e
  p [:outer_rescue, e]
ensure
  puts "outer ensure"
end
puts "not reached"
