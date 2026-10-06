src = "raise 'boom'"
begin
  eval(src)
rescue => e
  puts e.backtrace.first(2)
end
