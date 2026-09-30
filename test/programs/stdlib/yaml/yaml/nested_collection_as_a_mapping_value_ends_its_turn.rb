# A collection that is the value of a mapping key takes that key's turn, so the
# next node is a key again; a collection as a key shares its `?` line.

require "yaml"
puts({"a"=>[1,nil,true],"b"=>{"c"=>1, "e" => {"f" => [2]}}, "d" => "x"}.to_yaml)
puts [{"a"=>{"b"=>[1]}, "g" => 3}, 2].to_yaml
puts({[1, 2] => {"x" => 1}, "y" => []}.to_yaml)
p YAML.load({"a"=>[1],"b"=>{"c"=>1}}.to_yaml)
puts({{"a"=>1, "b"=>2} => [3, {"z"=>1}], [[1]] => 1, "k" => {[1] => {[2] => 3}}}.to_yaml)
puts [[[1, 2]], {"a" => {"b" => [[1]]}}].to_yaml
a = [1]
puts({"p" => a, "q" => a, "r" => {"s" => a}}.to_yaml)

