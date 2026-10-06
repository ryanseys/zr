# Hashes compare by VALUE across storage variants, like arrays: Ruby has one
# Hash, and a hash built at run time (JSON.parse) equals the same pairs
# written as a literal. `.class` on each one prints `Hash`.
require "json"
a = JSON.parse('{"k": 1}')
b = { "k" => 1 }
p a == b
p b == a
p a != b
puts a.class
p JSON.parse('{"k": "s", "n": [1, 2]}') == { "k" => "s", "n" => [1, 2] }
p JSON.parse('{"k": 1}') == { "k" => 2 }
p JSON.parse('{"k": 1}') == { "j" => 1 }
p JSON.parse('{"k": 1}') == { "k" => 1, "j" => 2 }
p JSON.parse('{"k": 1}') == [1]
p JSON.parse('{"k": 1}') == { "k" => 1.0 }   # 1 == 1.0
