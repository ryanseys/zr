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

