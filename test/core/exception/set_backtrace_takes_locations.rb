# set_backtrace with an Array of Locations sets backtrace_locations as
# well as the strings, and a raise keeps them; an eval SyntaxError holds
# the locations of the eval.
e = RuntimeError.new("x"); l = caller_locations(0); r = e.set_backtrace(l); p r.equal?(l), e.backtrace_locations.equal?(l), e.backtrace_locations.map(&:to_s), e.backtrace, (e.set_backtrace([l[0], "s"]) rescue $!)
e2 = RuntimeError.new; p e2.set_backtrace(["a"]), e2.backtrace_locations, RuntimeError.new.set_backtrace("x"), RuntimeError.new.set_backtrace(nil)
begin; raise e; rescue => x; p x.backtrace_locations.map(&:to_s); end
begin
  eval("1 +")
rescue SyntaxError => e
  p e.backtrace_locations.map(&:label)
end

__END__
true
false
["core/exception/set_backtrace_takes_locations.rb:4:in '<main>'"]
["core/exception/set_backtrace_takes_locations.rb:4:in '<main>'"]
#<TypeError: backtrace must be an Array of String or an Array of Thread::Backtrace::Location>
["a"]
nil
["x"]
nil
["core/exception/set_backtrace_takes_locations.rb:4:in '<main>'"]
["Kernel#eval", "<main>"]
