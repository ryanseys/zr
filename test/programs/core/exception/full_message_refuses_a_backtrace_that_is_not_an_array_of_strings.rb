# full_message reads an overridden backtrace as rb_get_backtrace does: one
# that is not an Array of Strings or Locations raises TypeError
# (test_exception.rb's test_wrong_backtrace).
error_class = Class.new(StandardError) do
  def backtrace; :backtrace; end
end
begin
  raise error_class
rescue error_class => e
  begin
    e.full_message
  rescue TypeError => t
    p [t.class, t.message]
  end
end
ok = Class.new(StandardError) { def backtrace = ["a:1", "b:2"] }
p ok.new("m").full_message(highlight: false).lines.size
