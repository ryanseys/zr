# A method parameter that the body reads as a Hash (`row["id"]`), and a
# caller that passes nil. As in CRuby, `nil["id"]` raises NoMethodError,
# so the program stops at the first call.

# Single caller that passes nil.

def consume(row)
  puts "id=" + row["id"].to_s
end

class Box
  attr_accessor :contents
end

b = Box.new
consume(b.contents)  # nil: no code sets the attribute

# Mixed callers: a hash literal and a nil value.

def fetch(row)
  puts "title=" + row["title"].to_s
end

fetch({"title" => "Real Hash"})
fetch(b.contents)
fetch({"title" => "Another Real"})

# Symbol-keyed lookup.

def grab(opts)
  puts "name=" + opts[:name].to_s
end

grab({name: "Sym Hash"})
grab(b.contents)
