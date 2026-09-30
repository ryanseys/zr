# Same home-escape-via-exception case as proc_return_escape_localjump, but the
# exception is caught by an *expression-form* `rescue` modifier. The method
# that made the proc has returned, so the later return raises LocalJumpError.
$escaped = nil
def home
  $escaped = proc { return 99 }
  raise "boom"
end
v = (home rescue 123)
p v
begin
  $escaped.call
  puts "WRONG: no error"
rescue LocalJumpError => e
  puts "localjump: #{e.message}"
end
