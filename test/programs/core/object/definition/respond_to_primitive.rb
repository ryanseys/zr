# `<primitive>.respond_to?(name)` answers true for the common method
# set, not just for obj-typed receivers.

puts 1.respond_to?(:to_s)
puts "x".respond_to?(:class)
puts :s.respond_to?(:inspect)
puts 1.5.respond_to?(:nil?)
puts [].respond_to?(:dup)
