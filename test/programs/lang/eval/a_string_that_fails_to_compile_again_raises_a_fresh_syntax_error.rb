# An eval of a string that does not compile raises a fresh SyntaxError
# each time, with the same message and a backtrace from the call, and a
# loop of them stays fast (test_eval.rb's test_syntax_error_no_memory_leak).
def try(src)
  eval(src)
rescue SyntaxError => e
  [e.class, e.message.lines.first.chomp.sub(/\(eval at [^)]*\)/, "(eval)"), e.backtrace.first[/:\d+:in/], e.backtrace.size > 1]
end
3.times { p try("/[/=~s") }
p try("1 +")
p try("1 +")
errors = 2.times.map { begin; eval("1 +"); rescue SyntaxError => e; e; end }
p errors[0].equal?(errors[1]), errors[0].message == errors[1].message
20_000.times do
  eval("/[/=~s")
rescue SyntaxError
end
p :done
