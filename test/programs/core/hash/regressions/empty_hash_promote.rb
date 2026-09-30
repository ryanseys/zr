# An empty hash literal takes the key and value types of its first []=
# write. So `h = {}; h[1] = "one"` gives a hash with Integer keys and
# String values.

# Empty -> string keys, int values
h1 = {}
h1["k"] = 1
h1["m"] = 2
puts h1["k"]
puts h1["m"]
puts h1.length

# Empty -> string keys, string values
h2 = {}
h2["x"] = "alpha"
h2["y"] = "beta"
puts h2["x"]
puts h2["y"]
puts h2.length

# Empty -> int keys, string values
h3 = {}
h3[1] = "one"
h3[2] = "two"
puts h3[1]
puts h3[2]
puts h3.length

# Empty -> sym keys, int values
h4 = {}
h4[:a] = 10
h4[:b] = 20
puts h4[:a]
puts h4[:b]
puts h4.length

# Empty -> sym keys, string values
h5 = {}
h5[:name] = "ada"
h5[:role] = "scientist"
puts h5[:name]
puts h5[:role]
puts h5.length
