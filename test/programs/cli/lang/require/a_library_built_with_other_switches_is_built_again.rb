# The same library file, built for programs with other switches: gems
# off, then on, then frozen string literals. Each build gives the file the
# code of its own switches, also when an earlier build kept the file's
# code for the next one. With gems on, the library's require of rubygems
# loads it as ruby's boot does, and warns of nothing under -w.
require "tmpdir"

Dir.mktmpdir do |dir|
  File.write("#{dir}/a_switched_library.rb", <<~'RUBY')
    require "rubygems"
    p Gem::VERSION.class, "a".frozen?
  RUBY
  [["--disable=gems"], [], ["--enable=frozen-string-literal"]].each do |options|
    puts "== #{options.join(" ")}"
    out = IO.popen([RbConfig.ruby, "-w", *options, "-I", dir, "-e", 'require "a_switched_library"'], err: [:child, :out], &:read)
    puts out
    p $?.exitstatus
  end
end
