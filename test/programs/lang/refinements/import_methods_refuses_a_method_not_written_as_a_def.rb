m = Module.new { attr_reader :q }
begin
  Module.new { refine(String) { import_methods m } }
rescue ArgumentError => e
  p e.message.sub(/#<Module:0x\h+>/, "M")
end
