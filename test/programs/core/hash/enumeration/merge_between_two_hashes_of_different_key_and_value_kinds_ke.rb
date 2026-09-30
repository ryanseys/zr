# Hash#merge between hashes of different key and value kinds keeps the
# pairs of both.
merged = { 14 => nil }.merge({ 39 => 1 })
p merged.keys.sort
p merged[14]
p merged[39]
p({ 1 => 2 }.merge({ "a" => "b" }))
p({ a: 1 }.merge({ "x" => 2 }))
p({ 1 => 2 }.merge({ 3 => "s" }))
