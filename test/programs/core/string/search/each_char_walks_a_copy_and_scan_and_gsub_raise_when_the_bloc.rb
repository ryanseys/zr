s = "abc".dup
r = []
s.each_char { |c| r << c; s.clear }
p r
begin
  s = "abc".dup
  s.gsub(/./) { s.clear; "x" }
rescue RuntimeError => e
  p e.message
end
begin
  s = "abc".dup
  s.scan(/./) { s << "d" }
rescue RuntimeError => e
  p e.message
end
