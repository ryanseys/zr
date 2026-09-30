# sleep with a poly argument (a duration pulled from a heterogeneous hash)
# sleeps for that Float.
h = { "t" => 0.0, "n" => 2 }
sleep(h["t"])   # poly value, holds a Float
puts "slept"
