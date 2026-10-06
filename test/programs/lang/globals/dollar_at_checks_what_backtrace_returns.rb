# `$@` is the backtrace of `$!`: nil outside a rescue, and a TypeError
# when an override of backtrace returns neither nil nor an Array of
# Strings or Locations.
p $@
begin
  raise "x"
rescue
  p $@.class
end
odd = Class.new(StandardError) { def backtrace = :backtrace }
begin
  raise odd
rescue odd => e
  begin
    $@
  rescue TypeError => t
    p t.message
  end
  p((e.full_message rescue $!.class))
end
