# While a thread reads an autoload's file, the constant that the file
# assigns is that thread's own until the file ends. So for another
# thread, `const_source_location` still gives the place of `autoload`,
# and the loading thread gets the place of the new constant.
def place(found) = found && [File.basename(found[0]), found[1]]

module Places
  autoload :Assigned, File.expand_path("source_during_autoload/assigned", __dir__)
end

checks = {
  "Module#const_source_location" => -> { Places.const_source_location(:Assigned) },
  "Object.const_source_location with a path" => -> { Object.const_source_location("Places::Assigned") },
}
seen = Hash.new { |h, k| h[k] = [] }
checks.each { |name, check| seen[name] << place(check.call) }

to_loader, from_loader = Queue.new, Queue.new
$during = lambda do
  from_loader.push(checks.transform_values { |check| place(check.call) })
  to_loader.pop
end
other = Thread.new do
  in_loader = from_loader.pop
  in_other = checks.transform_values { |check| place(check.call) }
  # The other thread also sees the name as declared, not yet loaded.
  in_other["autoload?"] = Places.autoload?(:Assigned) && :pending
  to_loader.push(:done)
  [in_loader, in_other]
end
Places::Assigned
in_loader, in_other = other.value

checks.each_key do |name|
  seen[name] << in_loader[name] << in_other[name] << place(checks[name].call)
end
seen.each { |name, places| puts "#{name}: #{places.inspect}" }
p in_other["autoload?"]
p Places.autoload?(:Assigned)
