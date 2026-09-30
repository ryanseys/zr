class Bad
  def pretty_print(q) = raise("in pp")
end
begin
  pp Bad.new
rescue => e
  puts e.backtrace.grep_v(/prettyprint|pp\.rb/).first(3)
end
