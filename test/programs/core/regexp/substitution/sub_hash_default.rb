# A Hash replacement in #sub/#gsub answers its default for a key it does not
# have, not always the empty string.
h = Hash.new("?")
h["e"] = "3"
p "hello".sub(/l/, h)
p "hello".sub(/e/, h)
p "hello".gsub(/l/, h)
g = { "e" => "3" }
p "hello".sub(/l/, g)
p "hello".sub(/e/, g)
