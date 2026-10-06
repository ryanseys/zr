# A module_function that can answer a String or nil, called with a
# string-literal arg from inside a string interpolation that is passed to
# Regexp.new/compile.
module StringGlob
  module_function
  def regexp_string(s)
    return nil if s.empty?
    s.gsub("*", ".*")
  end
end

re1 = Regexp.new("\\A#{StringGlob.regexp_string('*.rb')}\\z")
puts re1 === 'hello.rb'
puts re1 === 'hello.txt'

re2 = Regexp.compile("\\A#{StringGlob.regexp_string('*.txt')}\\z")
puts re2 === 'notes.txt'
