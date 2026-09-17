# Records the answer of the ruby the .ruby-version pins under `__END__`
# of each case named on the command line, in the trailer format of
# docs/reference/test-format.md. A path is taken relative to test/, or as it
# stands when it already points into it.
#
#   ruby tools/record.rb core/io/a_stream_reads_what_it_holds.rb
#   ruby tools/record.rb --os linux core/io/a_stream_reads_what_it_holds.rb
#
# A case that carries a trailer already is left alone: a recording is
# made once, and a change of answer is a change of program.
#
# `--os linux` or `--os wasi` runs on that platform's ruby instead, and
# writes that platform's sections of a case macOS recorded: the ones
# where its answer parts from macOS's, in place of the ones it wrote
# before. `--ruby "<command>"` names that ruby when `ruby` is not it, as
# ruby.wasm under wasmtime is not.
require "open3"
require "shellwords"
require_relative "../test/support/harness/case"

ROOT = File.expand_path("../test", __dir__)

# A body line that would read as a marker takes one more `#`, which the
# reader strips again.
def escaped(text) = text.gsub(/^(#+@)/, '#\1')

# A section of the trailer: the bytes, and the note that says when the
# last line of them has no newline of its own.
def section(text) = text.empty? || text.end_with?("\n") ? escaped(text) : "#{escaped(text)}\n#@ nonl\n"

# The header directives that shape the run of the oracle. The others
# (`zeo:`, `only:`, `needs:`, `backend:`) say nothing about ruby.
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

# The status marker `prefix` leads, or nil for an exit of 0.
def status_marker(status, prefix = "")
  return "#@ #{prefix}signal #{status.termsig}\n" if status.signaled?

  "#@ #{prefix}exit #{status.exitstatus}\n" unless status.exitstatus.zero?
end

def trailer_of(out, err, status)
  trailer = +"\n__END__\n"
  trailer << section(out) unless out.empty?
  trailer << "#@ stderr\n" << section(err) unless err.empty?
  trailer << status_marker(status).to_s
  trailer
end

# `os`'s sections: each of stdout, stderr and the status where the
# answer parts from macOS's.
def sections_of(os, macos, out, err, status)
  text = +""
  text << "#@ #{os} stdout\n" << section(out) unless out.b == macos.stdout
  text << "#@ #{os} stderr\n" << section(err) unless err.b == macos.stderr
  same = status.signaled? ? macos.signal == status.termsig : macos.signal.nil? && macos.code == status.exitstatus
  text << (status_marker(status, "#{os} ") || "#@ #{os} exit 0\n") unless same
  text
end

# The trailer without `os`'s sections: from each of its markers up to the
# next marker that is not its own.
def without(trailer, os)
  inside = false
  trailer.each_line.reject do |line|
    if line.start_with?("#@ ")
      words = line.split
      inside = words[1] == os unless words[1] == "nonl"
    end
    inside
  end.join
end

options = { os: nil, ruby: ["ruby"] }
while ARGV.first&.start_with?("--")
  case ARGV.shift
  when "--os" then options[:os] = ARGV.shift
  when "--ruby" then options[:ruby] = Shellwords.split(ARGV.shift.to_s)
  else ARGV.clear
  end
end
os = options[:os]
if ARGV.empty? || (os && !Ze0::Harness::Case::PREFIXED.include?(os))
  abort "usage: ruby tools/record.rb [--os #{Ze0::Harness::Case::PREFIXED.join("|")}] [--ruby <command>] <case path>..."
end

Dir.chdir(ROOT) do
  ARGV.each do |name|
    path = name.delete_prefix("#{ROOT}/").delete_prefix("test/")
    source = File.read(path)
    recorded = source.match?(/^__END__$/)
    abort "#{path}: already recorded" if recorded && os.nil?
    abort "#{path}: macOS's answer comes first" if os && !recorded

    arguments, env, stdin = directives(source, path)
    # RUBYOPT is cleared so that what the shell carries cannot reach the
    # answer a case records.
    out, err, status = Open3.capture3(env.merge("RUBYOPT" => nil), *options[:ruby], *arguments,
                                      stdin_data: stdin ? File.binread(stdin) : "")
    if os
      program, trailer = source.split(/^__END__\n?/, 2)
      trailer = without(trailer.to_s, os)
      added = sections_of(os, Ze0::Harness::Case.new(source, path).expected, out, err, status)
      File.write(path, "#{program}__END__\n#{trailer}#{added}")
      apart = added.scan(/^#@ #{os} (\w+)/).flatten
      puts "recorded #{os} for #{path}: #{apart.empty? ? "the same as macOS" : apart.join(", ")}"
    else
      trailer = trailer_of(out, err, status)
      File.write(path, source + trailer)
      puts "recorded #{path} (#{status.signaled? ? "signal #{status.termsig}" : "exit #{status.exitstatus}"})"
      print trailer
    end
  end
end
