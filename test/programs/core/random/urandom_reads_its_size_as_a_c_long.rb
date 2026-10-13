# Random.urandom reads its size as a C long, as NUM2LEN does (ruby 4.1):
# a Float truncates, an object converts through to_int, and a size past
# the range of a long raises RangeError before any byte is drawn.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end

three = Object.new
def three.to_int = 3

sizes = {
  "0" => 0, "1" => 1, "16" => 16, "2.9" => 2.9, "to_int 3" => three,
  "-1" => -1, "-1.5" => -1.5,
  "2**63" => 2**63, "-2**63 - 1" => -2**63 - 1, "2**64" => 2**64,
  "2.0**63" => 2.0**63, "NaN" => Float::NAN, "Infinity" => Float::INFINITY,
  "nil" => nil, "\"3\"" => "3", ":a" => :a
}
sizes.each do |label, size|
  t("urandom(#{label})") do
    s = Random.urandom(size)
    [s.bytesize, s.encoding, s.frozen?]
  end
end

# Two draws of 16 bytes differ.
p Random.urandom(16) != Random.urandom(16)
