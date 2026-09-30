# There is no compile-time `attributes` DSL: CRuby (and
# zr) raise NoMethodError when the class body executes. Rescued inside
# the body so the output is path-portable.
class BadAttributes
  begin
    attributes "name"
  rescue NoMethodError => e
    puts "rescued: #{e.message}"
  end
end
puts "after"
