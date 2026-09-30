P = Data.define(:x, :y)
p P.new("x" => 1, "y" => 2), P.new("x" => 1, y: 2)
[-> { P.new(1 => 1, 2 => 2) }, -> { P.new("x" => 1, "y" => 2, "z" => 3) }, -> { P.new(x: 1, "z" => 2) }].each do |f|
  f.call
rescue ArgumentError, TypeError => e
  p [e.class, e.message]
end
