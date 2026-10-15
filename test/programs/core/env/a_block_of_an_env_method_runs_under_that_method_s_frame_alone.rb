# ENV.update (merge!), fetch and delete run their block in C, so an
# error in the block shows the method's frame and no frame of an
# iteration inside it.
ENV["FRAMES_A"] = "1"
calls = {
  update: -> { ENV.update("FRAMES_A" => "2") { |*| raise "x" } },
  merge!: -> { ENV.merge!({ "FRAMES_A" => "2" }, { "FRAMES_B" => "3" }) { |*| raise "x" } },
  fetch: -> { ENV.fetch("FRAMES_NONE") { raise "x" } },
  delete: -> { ENV.delete("FRAMES_NONE") { raise "x" } },
}
calls.each do |name, call|
  call.call
rescue RuntimeError => e
  puts "#{name}: #{e.backtrace.map { |l| l[/'[^']+'/] }.join(' < ')}"
end
p ENV["FRAMES_A"], ENV["FRAMES_B"]
