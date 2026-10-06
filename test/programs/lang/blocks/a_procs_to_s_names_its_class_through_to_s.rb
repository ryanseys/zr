# Proc#to_s names the Proc's class through the class's own to_s, as
# rb_block_to_s writes it.
named = Class.new(Proc) do
  singleton_class.class_eval { define_method(:to_s) { "Proc\u{1f37b}" } }
end
text = named.new {}.to_s
p [text.include?("Proc\u{1f37b}"), text.encoding]
p proc {}.to_s.sub(/0x\h+/, "0xADDR").sub(/ \S+:\d+>/, " FILE>")
p lambda {}.to_s.sub(/0x\h+/, "0xADDR").sub(/ \S+:\d+ /, " FILE ")
