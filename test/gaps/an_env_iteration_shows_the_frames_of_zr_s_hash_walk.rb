# ENV's iterating methods walk the variables in C, so an error in the
# block shows only the method's frame. zr's ENV walks a Hash of the
# variables, so the frame of that Hash's or Array's method shows too.
ENV["FRAMES_A"] = "1"
# rubocop:disable Lint/UnreachableLoop
calls = {
  each: -> { ENV.each { raise "x" } },
  each_pair: -> { ENV.each_pair { raise "x" } },
  each_key: -> { ENV.each_key { raise "x" } },
  each_value: -> { ENV.each_value { raise "x" } },
  select: -> { ENV.select { raise "x" } },
  filter: -> { ENV.filter { raise "x" } },
  reject: -> { ENV.reject { raise "x" } },
  select!: -> { ENV.select! { raise "x" } },
  reject!: -> { ENV.reject! { raise "x" } },
  keep_if: -> { ENV.keep_if { raise "x" } },
  delete_if: -> { ENV.delete_if { raise "x" } },
  filter_map: -> { ENV.filter_map { raise "x" } },
  to_h: -> { ENV.to_h { raise "x" } },
  any?: -> { ENV.any? { raise "x" } },
  map: -> { ENV.map { raise "x" } },
}
# rubocop:enable Lint/UnreachableLoop
calls.each do |name, call|
  call.call
rescue RuntimeError => e
  puts "#{name}: #{e.backtrace.map { |l| l[/'[^']+'/] }.join(' < ')}"
end
