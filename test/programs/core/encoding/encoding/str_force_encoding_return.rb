# `def f(s); s.force_encoding(...); end` returns the String, because
# `force_encoding` returns its receiver. The same holds for encode / b.

def normalize(s)
  s.force_encoding("UTF-8")
end

def utf8_to_bin(s)
  s.encode("ASCII-8BIT")
end

def to_binary(s)
  s.b
end

puts normalize("hello")
puts utf8_to_bin("world")
puts to_binary("bytes")
