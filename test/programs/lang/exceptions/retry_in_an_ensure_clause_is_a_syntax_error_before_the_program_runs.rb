# A retry in an ensure clause has no rescue clause to run again, though a
# rescue clause encloses the begin that holds it. Ruby's compiler raises
# SyntaxError, so no line of the program runs.
puts "never"
tries = 0
begin
  tries += 1
  raise "again" if tries < 2
rescue
  begin
    nil
  ensure
    retry
  end
end
p tries
