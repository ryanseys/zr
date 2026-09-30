# A write that fills the buffer joins text in any two encodings: the
# buffer holds bytes.
$stdout.write "é".b * 4095
puts "é" * 10
$stdout.write "\n"
p $stdout.write("x".b * 9000, "日")

