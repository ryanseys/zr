# A required file that does not parse raises SyntaxError where the require
# runs, with the file as its path; the program goes on after a rescue.
begin
  require_relative "unparsable_helper"
rescue SyntaxError => e
  p e.class, File.basename(e.path)
end
puts "after"
