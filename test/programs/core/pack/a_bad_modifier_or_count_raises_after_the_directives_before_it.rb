# pack and unpack read the template as they go: a directive with a bad
# modifier, a bad count or a `%` raises only once the directives before
# it are done, so an earlier directive's own error comes first.
def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue ArgumentError, RangeError, TypeError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

try("A then b_, no items") { [].pack("Ab_c-D") }
try("A then b_, one item") { ["a"].pack("Ab_") }
try("b_ alone") { [].pack("b_") }
try("C then a_") { [].pack("Ca_") }
try("C then %") { [].pack("C%") }
try("C then %, one item") { [1].pack("C%") }
try("C then s<>") { [].pack("Cs<>") }
try("C then s<>, one item") { [1].pack("Cs<>") }
try("a then huge count") { [].pack("aC99999999999999999999") }
try("a then x! with no alignment") { [].pack("ax!") }
try("a then unknown") { [].pack("ay") }
try("q then a!") { [1.5r].pack("qa!") }
try("q then a!, String") { ["x"].pack("qa!") }
try("U then b_") { [-1].pack("Ub_") }

try("unpack m then b_") { "!!".unpack("m0b_") }
try("unpack X then b_") { "".unpack("Xb_") }
try("unpack C then b_") { "a".unpack("Cb_") }
try("unpack @ then %") { "a".unpack("@5%") }
try("unpack1 C then b_") { "a".unpack1("Cb_") }
try("unpack1 C then unknown") { "a".unpack1("Cy") }

# The result's encoding still follows every directive packed.
try("U then a") { [0x263a, "x"].pack("Ua").encoding }
try("m then U") { ["x", 0x263a].pack("mU").encoding }
try("u then m") { ["x", "y"].pack("um").encoding }
