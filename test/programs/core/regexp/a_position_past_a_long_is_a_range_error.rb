# A search position goes through NUM2LONG: a Bignum is a RangeError
# however far past the text it points, and a Float truncates.
def try(label)
  r = yield
  r = r[0] if r.is_a?(MatchData)
  puts "#{label}: #{r.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

big = 2**64
[big, -big, 2**63, -(2**63) - 1].each do |pos|
  try("Regexp#match? #{pos}") { /d/.match?("b!", pos) }
  try("String#match? #{pos}") { "b!".match?("%d", pos) }
  try("String#match? Regexp #{pos}") { "b!".match?(/d/, pos) }
  try("Symbol#match? #{pos}") { :b!.match?("%d", pos) }
  try("Regexp#match #{pos}") { /d/.match("b!", pos) }
  try("String#match #{pos}") { "b!".match(/d/, pos) }
  try("Symbol#match #{pos}") { :b!.match(/d/, pos) }
  try("String#index #{pos}") { "b!".index("d", pos) }
  try("String#rindex #{pos}") { "b!".rindex("d", pos) }
  try("String#byteindex #{pos}") { "b!".byteindex("d", pos) }
  try("String#byterindex #{pos}") { "b!".byterindex("d", pos) }
end

try("match? Float") { /!/.match?("b!", 1.9) }
try("match? Float past") { /!/.match?("b!", 2.5) }
try("match? to_int") { /!/.match?("b!", Object.new.tap { |o| def o.to_int = 1 }) }
try("match? nil") { /!/.match?("b!", nil) }
try("match? String") { /!/.match?("b!", "1") }
try("match? nil text, big") { /!/.match?(nil, big) }
try("match nil text, big") { /!/.match(nil, big) }
try("match nil text, nil") { /!/.match(nil, nil) }
try("match Float") { /!/.match("b!", 1.9) }
