# frozen_string_literal: true

# Which files of a corpus directory ze0 compiles, and what it refuses.
#
#   ruby ze0/scan.rb 'test/lang/blocks/*.rb' 40
#
# One ruby process per file, and a limit, because ze0 compiling
# thousands of files in ONE process takes the machine down. The compile
# is all that runs: nothing is linked.
require "tmpdir"
require "rbconfig"

glob = ARGV[0] || abort("usage: ruby ze0/scan.rb <glob> [limit]")
files = Dir[glob].sort.first(Integer(ARGV[1] || 40))
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
puts "#{ok} of #{files.size} compiled"
