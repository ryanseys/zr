# ENV's iterating methods walk the variables in C, so an error in the
# block shows only the method's frame. The bang forms and select, filter
# and reject read each value again at its turn, so a block that changes
# ENV is seen; each and its kin read every pair before the first yield.
ENV.keys.grep(/\AFRAMES_/).each { |name| ENV.delete(name) }
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
  filter!: -> { ENV.filter! { raise "x" } },
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

def mine(hash) = hash.select { |k, _| k.start_with?("FRAMES_") }.sort.to_h

ENV["FRAMES_B"] = "2"
ENV["FRAMES_C"] = "3"
p mine(ENV.select { |k, v| k.start_with?("FRAMES_") && v != "2" })
p mine(ENV.reject { |k, _| k == "FRAMES_A" })
p mine(ENV.filter { |_, v| v == "3" })
p ENV.to_h { |k, v| [k.downcase, v] }.select { |k, _| k.start_with?("frames_") }.sort
p((ENV.to_h { 1 } rescue $!), (ENV.to_h { [1] } rescue $!))

seen = []
ENV.each { |k, v| seen << [k, v] if k.start_with?("FRAMES_"); ENV.delete("FRAMES_C") if k == "FRAMES_A" }
p seen.sort
ENV["FRAMES_C"] = "3"

seen = []
p mine(ENV.select { |k, v| ENV.delete("FRAMES_C") if k == "FRAMES_A"; seen << k if k.start_with?("FRAMES_"); true })
p seen.sort
ENV["FRAMES_C"] = "3"

p ENV.reject! { |k, _| k == "FRAMES_C" }.equal?(ENV), ENV.reject! { false }
p ENV.select! { true }, ENV.filter! { |k, _| k != "FRAMES_B" }.equal?(ENV)
p ENV.delete_if { false }.equal?(ENV), ENV.keep_if { true }.equal?(ENV)
p mine(ENV.to_h)
p ENV.each_key.size == ENV.size, ENV.select.class, ENV.each_pair { }.equal?(ENV)
keys = []
ENV.each_key { |k| keys << k if k.start_with?("FRAMES_") }
values = []
ENV.each_value { |v| values << v if v == "1" }
p keys.sort, values.uniq
ENV.keys.grep(/\AFRAMES_/).each { |name| ENV.delete(name) }
