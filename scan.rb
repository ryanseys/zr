# frozen_string_literal: true

# Which files of a corpus directory ze0 compiles, and what it refuses.
#
#   ruby ze0/scan.rb 'test/lang/blocks/*.rb'
#   ruby ze0/scan.rb 'test/lang/blocks/*.rb' 40    # the first 40 only
#
# One ruby process per file, because ze0 compiling thousands of files in
# ONE process takes the machine down. The compile is all that runs:
# nothing is linked, so this says which programs ze0 REFUSES and nothing
# about which ones it gets right -- `cargo xtask ze0-sweep` answers that.
require "tmpdir"
require "rbconfig"

glob = ARGV[0] || abort("usage: ruby ze0/scan.rb <glob> [limit]")
found = Dir[glob].sort
files = ARGV[1] ? found.first(Integer(ARGV[1])) : found
out = File.join(Dir.tmpdir, "ze0-scan.clif")

refusals = Hash.new(0)
ok = 0
files.each do |file|
  message = IO.popen([RbConfig.ruby, "ze0/ze0.rb", file, "-o", out], err: %i[child out], &:read)
  if message.empty?
    ok += 1
    next
  end

  # The line number is the file's; the SHAPE is what is being counted.
  what = message.lines.first.strip
  refusals[what.sub(/\A.*?: line \d+: /, "").sub(" is not in ze0's subset", "")] += 1
end

refusals.sort_by { |_, n| -n }.each { |what, n| puts format("%4d  %s", n, what) }
puts "#{ok} of #{files.size} compiled" +
     (files.size < found.size ? " (#{found.size} match the glob)" : "")
