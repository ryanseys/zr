# An edit in place whose backup cannot be made warns with the file's
# name, which can hold characters that are not ASCII.
require "tmpdir"
require "stringio"
Dir.mktmpdir do |dir|
  name = "#{dir}/argf-\u{30c6 30b9 30c8}"
  File.write(name, "foo")
  argf = ARGF.class.new(name)
  argf.inplace_mode = '/\\:'
  $stderr = StringIO.new
  p argf.gets
  text = $stderr.string
  $stderr = STDERR
  p text.include?("argf-\u{30c6 30b9 30c8}"), text.include?("skipping file")
end
