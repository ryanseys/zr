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

  # A loaded constant is the copy's own, and the copy's constants are its own.
  m3 = Module.new { const_set(:Y, 2) }
  m4 = m3.dup
  m4.const_set(:Z, 3)
  m4.send(:remove_const, :Y)
  p m3.constants.sort, m4.constants.sort, m3::Y
end
