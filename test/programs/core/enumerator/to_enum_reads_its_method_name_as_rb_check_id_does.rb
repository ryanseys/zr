# to_enum and enum_for take the method's name as a Symbol, a String, or
# what to_str gives, as enumerator_init's rb_check_id reads it; any other
# value is a TypeError, before anything runs.
def show(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

o = Object.new
[0, nil, 1.5, [:each], { a: 1 }, true].each do |name|
  show("to_enum(#{name.inspect})") { o.to_enum(name) }
  show("enum_for(#{name.inspect})") { o.enum_for(name, 1) }
  show("lazy to_enum(#{name.inspect})") { [1].lazy.to_enum(name) }
end
show("a String") { [1, 2].enum_for("map").with_index.to_a }
show("a Symbol") { [1, 2].to_enum(:each_slice, 1).to_a }
show("to_str") do
  name = Object.new
  def name.to_str = "each"
  [1].enum_for(name).to_a
end
show("an unknown name") { o.to_enum(:nope).size }
show("lazy String") { [1, 2].lazy.enum_for("map").first(1) }
