# remove_const on a name whose autoload has not run answers nil, and
# the name forgets its file as well as its row.
module Box
  autoload :Later, "/nonexistent/later_for_remove_const.rb"
end
p Box.autoload?(:Later), Box.const_defined?(:Later)
p Box.send(:remove_const, :Later)
p Box.autoload?(:Later), Box.const_defined?(:Later), Box.constants
begin
  Box.send(:remove_const, :Later)
rescue NameError => e
  p e.message
end

__END__
"/nonexistent/later_for_remove_const.rb"
true
nil
nil
false
[]
"constant Box::Later not defined"
