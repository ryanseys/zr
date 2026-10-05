# A thread that reads a name while another thread reads the name's
# autoload file waits for the file to end, even when the file has already
# set the name, as in test_autoload.rb's threaded tests.
require "tmpdir"

Dir.mktmpdir do |dir|
  File.write(File.join(dir, "inner.rb"), "class AutoloadInner; sleep 0.3; X = 1; end\n")
  File.write(File.join(dir, "outer.rb"), "sleep 0.3; class AutoloadOuter; X = 2; end\n")
  autoload :AutoloadInner, File.join(dir, "inner.rb")
  autoload :AutoloadOuter, File.join(dir, "outer.rb")
  %i[AutoloadInner AutoloadOuter].each do |name|
    threads = Array.new(2) { Thread.new { Object.const_get(name)::X } }
    p threads.map(&:value)
  end
end
