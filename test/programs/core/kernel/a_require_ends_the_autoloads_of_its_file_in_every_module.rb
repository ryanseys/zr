# Each module keeps its own autoloads. A require of a file ends the wait
# of every autoload of that file, in modules made before it and in the
# copies of those modules; one made after it only declares the name.
require "tmpdir"

Dir.mktmpdir do |dir|
  File.write(File.join(dir, "shared_feature.rb"), "$loaded = ($loaded || 0) + 1\n")
  $LOAD_PATH.unshift(dir)
  feature = "shared_#{'feature'}"
  mods = Array.new(3) { Module.new.tap { |m| m.autoload(:Thing, feature) } }
  copy = mods[0].dup
  other = Module.new
  other.autoload(:Thing, "missing_#{'feature'}")
  p mods.map { |m| m.autoload?(:Thing) }, copy.autoload?(:Thing)
  p mods.map { |m| m.const_defined?(:Thing) }

  require feature
  p $loaded
  p mods.map { |m| m.autoload?(:Thing) }, copy.autoload?(:Thing), other.autoload?(:Thing)
  p mods.map { |m| m.const_defined?(:Thing) }, other.const_defined?(:Thing)
  late = Module.new
  late.autoload(:Thing, feature)
  p late.autoload?(:Thing), late.const_defined?(:Thing)
  begin
    mods[1]::Thing
  rescue NameError => e
    p e.message.sub(/#<Module:0x\h+>/, "M")
  end
  p $loaded

  many = Array.new(2000) { |i| Module.new.tap { |m| m.autoload(:Thing, "nothing_#{i}") } }
  p many.count { |m| m.autoload?(:Thing) }
  p many[1234].autoload?(:Thing)
ensure
  $LOAD_PATH.delete(dir)
end
