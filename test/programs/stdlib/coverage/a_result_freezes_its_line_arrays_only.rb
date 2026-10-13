# Coverage.result freezes the whole result and each file's lines, not a
# file's hash or its branches and methods.
require "coverage"
require "tmpdir"
def t(label)
  p [label, yield]
rescue Exception => e
  p [label, e.class, e.message.gsub(/0x\h+/, "0x")]
end
Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    File.write("covx.rb", "def a = 1\na\nx = 1 > 0 ? 1 : 2\n")
    Coverage.start(:all)
    load "./covx.rb"
    r = Coverage.result.values.first
    t(:coverage) { [r.frozen?, r[:lines].frozen?, r[:branches].frozen?, r[:methods].frozen?] }
    File.delete("covx.rb")
  end
end
