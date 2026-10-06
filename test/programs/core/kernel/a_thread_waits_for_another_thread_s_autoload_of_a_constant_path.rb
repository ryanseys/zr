# While one thread reads an autoload's file, the class that the file opens
# is that thread's own: another thread that reads the name, or a name
# inside it, waits for the file to end.
require "tmpdir"

Dir.mktmpdir do |dir|
  File.write(File.join(dir, "path_class.rb"), "class PathClass; sleep 0.2; X = 1; end\n")
  File.write(File.join(dir, "path_module.rb"), "module PathModule; sleep 0.2; Y = 2; end\n")
  File.write(File.join(dir, "path_nested.rb"), "module PathOuter; module Inner; sleep 0.2; Z = 3; end; end\n")

  Object.autoload(:PathClass, File.join(dir, "path_class.rb"))
  threads = [Thread.new { ::PathClass::X }, Thread.new { PathClass::X }, Thread.new { Object.const_get(:PathClass)::X }]
  p threads.map(&:value)

  Object.autoload(:PathModule, File.join(dir, "path_module.rb"))
  threads = [Thread.new { PathModule::Y }, Thread.new { PathModule.const_get(:Y) }, Thread.new { PathModule.constants.sort }]
  p threads.map(&:value)

  Object.autoload(:PathOuter, File.join(dir, "path_nested.rb"))
  threads = Array.new(3) { Thread.new { PathOuter::Inner::Z } }
  p threads.map(&:value)

  # Again and again, as the race may go either way.
  File.write(File.join(dir, "race.rb"), "class RaceClass; Thread.pass; X = :x; end\n")
  failures = 0
  20.times do
    Object.autoload(:RaceClass, File.join(dir, "race.rb"))
    pair = Array.new(2) { Thread.new { RaceClass::X } }
    pair.each do |t|
      t.join
    rescue NameError
      failures += 1
    end
    Object.send(:remove_const, :RaceClass)
    $LOADED_FEATURES.delete(File.join(dir, "race.rb"))
  end
  p failures
end
