# A `module_function` instance copy is PRIVATE, so an explicit receiver must
# raise NoMethodError -- including a builtin-derived method reached through
# an explicit-receiver call. `respond_to?` says false,
# `private_method_defined?` says true, and `public_send` raises correctly.
#
# Predates the module_function conversion -- `5.puts("x")` has always answered
# where ruby raises, for the same reason.

class Host
  include Process
end

begin
  Host.new.pid
  puts "no raise"
rescue NoMethodError => e
  puts e.message
end

begin
  5.puts("x")
  puts "no raise"
rescue NoMethodError => e
  puts e.message
end
