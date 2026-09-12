# Records the answer of the ruby the .ruby-version pins under `__END__`
# of each case named on the command line, in the trailer format of
# docs/test-format.md. A path is taken relative to test/, or as it
# stands when it already points into it.
#
#   ruby tools/record.rb core/io/a_stream_reads_what_it_holds.rb
#
# A case that carries a trailer already is left alone: a recording is
# made once, and a change of answer is a change of program.
require "open3"
require "shellwords"

ROOT = File.expand_path("../test", __dir__)

# A body line that would read as a marker takes one more `#`, which the
# reader strips again.
def escaped(text) = text.gsub(/^(#+@)/, '#\1')

# A section of the trailer: the bytes, and the note that says when the
# last line of them has no newline of its own.
def section(text) = text.end_with?("\n") ? escaped(text) : "#{escaped(text)}\n#@ nonl\n"

# The header directives that shape the run of the oracle. The others
# (`zeo:`, `only:`, `backend:`, `gccheck:`) say nothing about ruby.
def directives(source, path)
  head = source.split(/^__END__$/, 2).first
  rows = head.scan(/^#@ (\w+):[ \t]*(.*)$/).to_h
  env = rows["env"].to_s.split.to_h { |pair| pair.split("=", 2) }
  [
    Shellwords.split(rows["ruby"].to_s) + [path] + Shellwords.split(rows["args"].to_s),
    env,
    rows["stdin"] && File.expand_path(rows["stdin"], File.dirname(path)),
  ]
end

def trailer_of(out, err, status)
  trailer = +"\n__END__\n"
  trailer << section(out) unless out.empty?
  trailer << "#@ stderr\n" << section(err) unless err.empty?
  if status.signaled?
    trailer << "#@ signal #{status.termsig}\n"
  elsif status.exitstatus != 0
    trailer << "#@ exit #{status.exitstatus}\n"
  end
  trailer
end

abort "usage: ruby tools/record.rb <case path>..." if ARGV.empty?

Dir.chdir(ROOT) do
  ARGV.each do |name|
    path = name.delete_prefix("#{ROOT}/").delete_prefix("test/")
    source = File.read(path)
    abort "#{path}: already recorded" if source.match?(/^__END__$/)

    arguments, env, stdin = directives(source, path)
    # RUBYOPT is cleared so that what the shell carries cannot reach the
    # answer a case records.
    out, err, status = Open3.capture3(env.merge("RUBYOPT" => nil), "ruby", *arguments, stdin_data: stdin ? File.binread(stdin) : "")
    trailer = trailer_of(out, err, status)
    File.write(path, source + trailer)
    puts "recorded #{path} (#{status.signaled? ? "signal #{status.termsig}" : "exit #{status.exitstatus}"})"
    print trailer
  end
end
