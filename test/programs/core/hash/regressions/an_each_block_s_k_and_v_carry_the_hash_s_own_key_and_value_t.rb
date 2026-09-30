# In `h.each do |k, v|`, `k` is the key and `v` is the value, each
# with its own type. So `puts k + ": " + v.to_s` joins Strings.

h = { "a" => 1, "b" => 2 }
h.each do |k, v|
  puts k + ": " + v.to_s
end
