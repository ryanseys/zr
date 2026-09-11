# Once $stderr names another stream, warnings, abort's message and the
# report of an uncaught exception all go there.
$stderr = $stdout
warn "w"
$stderr.puts "direct"
begin
  abort "a"
rescue SystemExit
end
raise "boom"

__END__
w
direct
a
core/io/a_moved_stderr_takes_warnings_and_the_report.rb:10:in '<main>': boom (RuntimeError)
#@ exit 1
