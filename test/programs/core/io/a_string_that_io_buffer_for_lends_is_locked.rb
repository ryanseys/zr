# IO::Buffer.for with a block locks a String that is not frozen until the
# block ends: each change raises "can't modify string; temporarily
# locked". Each of IO::Buffer.for, .string and .new warns that it is
# experimental, once.
string = +"Hello World"
changes = {
  "[]=" => -> { string[0] = "h" },
  "<<" => -> { string << "!" },
  "replace" => -> { string.replace("x") },
  "upcase!" => -> { string.upcase! },
  "clear" => -> { string.clear },
  "concat" => -> { string.concat("y") },
  "force_encoding" => -> { string.force_encoding("BINARY") },
}
IO::Buffer.for(string) do |buffer|
  changes.each do |name, change|
    change.call
    puts "#{name}: changed"
  rescue => e
    puts "#{name}: #{e.class}: #{e.message}"
  end
  p [string.frozen?, buffer.get_string(0, 5)]
end
string[0] = "h"
p string
frozen = "Frozen".freeze
IO::Buffer.for(frozen) { |b| p b.get_string }
p frozen.frozen?
p IO::Buffer.string(3) { |b| b.set_string("abc") }
