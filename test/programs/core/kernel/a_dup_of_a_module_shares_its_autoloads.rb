# A copy of a module shares the autoloads its original still waits for:
# both name the file, and the file defines the name in the module it names.
require "tmpdir"

module DupHolder; end

Dir.mktmpdir do |dir|
  filename = File.join(dir, "t_file.rb")
  File.write(filename, "DupHolder::S::T = :autoload_t\n")
  mod1 = Module.new { autoload :T, filename }
  DupHolder::S = mod1
  mod2 = mod1.dup
  p mod1.autoload?(:T) == filename, mod2.autoload?(:T) == filename
  p mod1::T
  begin
    mod2::T
  rescue NameError => e
    p e.class
  end
  p mod2.autoload?(:T), mod2.constants
  
  # When the copy reads first, the file defines the name in the original
  # only. The copy loses the name, and the original keeps no autoload.
  File.write(File.join(dir, "u_file.rb"), "DupHolder::S2::U = :autoload_u\n")
  first = Module.new { autoload :U, File.join(dir, "u_file") }
  DupHolder::S2 = first
  copy = first.dup
  begin
    copy::U
  rescue NameError => e
    p e.message.sub(/#<Module:0x\h+>/, "M")
  end
  p [first.autoload?(:U), first.constants, copy.autoload?(:U), copy.constants]
  p first::U
  
  # Another module with an autoload of the same file still waits for it
  # after the read, and its own read then finds the name undefined.
  File.write(File.join(dir, "v_file.rb"), "DupHolder::S3::V = :autoload_v\n")
  v_path = File.join(dir, "v_file")
  orig = Module.new { autoload :V, v_path }
  DupHolder::S3 = orig
  twin = orig.dup
  other = Module.new { autoload :V, v_path }
  p orig::V
  p [twin.autoload?(:V) ? :waits : nil, twin.constants, other.autoload?(:V) ? :waits : nil, other.constants]
  begin
    other::V
  rescue NameError => e
    p e.message.sub(/#<Module:0x\h+>/, "M")
  end
  p other.constants

  # A loaded constant is the copy's own, and the copy's constants are its own.
  m3 = Module.new { const_set(:Y, 2) }
  m4 = m3.dup
  m4.const_set(:Z, 3)
  m4.send(:remove_const, :Y)
  p m3.constants.sort, m4.constants.sort, m3::Y
end
