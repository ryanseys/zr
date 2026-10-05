# File::Stat checks the owner's, the group's or the others' bit, and
# inspect shows its times as Time#inspect does. ENV strings go to
# Encoding.default_internal when it is set.
s = File.stat("/etc/passwd")
p s.writable?, s.readable?, s.executable?, s.readable_real?, s.owned?
p File.stat("/bin/ls").executable?, File.stat("/").executable?, File.stat(__FILE__).writable?
st = File.stat(__FILE__)
p st.inspect.include?("atime=#{st.atime.inspect}"), File.stat("/").inspect[/mode=\w+/]
ENV["ZRV"] = "x"
Encoding.default_internal = Encoding::IBM437
p ENV["ZRV"].encoding, ENV.to_h["ZRV"].encoding, ENV.each_pair.first.map(&:encoding).uniq, ENV["ZRV"].frozen?
Encoding.default_internal = nil
p ENV["ZRV"].encoding
