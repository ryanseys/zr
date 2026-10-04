# String#[]=: the place is found and checked before the replacement
# converts, a capture index converts with to_int and may count from the
# end, and an index and a count convert with to_int.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

value = Object.new
def value.to_str
  puts "to_str called"
  +"X"
end

s = +"hello"
show { s[/z/] = value }
show { s[/(l)/, 3] = value }
show { s[/(h)(e)/, -2] = +"H" }
p s
group = Object.new
def group.to_int = 2
show { s[/(H)(e)/, group] = +"E" }
p s
bad = Object.new
def bad.to_int = "1"
show { s[/(H)/, bad] = +"x" }

index = Object.new
def index.to_int = 1
count = Object.new
def count.to_int = 2
t = +"abcdef"
t[index, count] = value
p t
show { t[0, bad] = +"x" }
show { t[20, 1] = value }
