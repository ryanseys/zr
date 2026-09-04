# Census: what ze0 refuses, over a corpus, ranked by how often.
#
#   ruby ze0/census.rb 'test/lang/**/*.rb' 'test/core/**/*.rb'
#   ruby ze0/census.rb 'vendor/gems/gems/*/lib/**/*.rb'
#
# Two passes over the same files. The FIRST REFUSAL says what blocks each
# file, which is what a person fixing ze0 works through. The NODE census
# says which Prism node kinds ze0's lowering never names at all, which
# catches every form hidden behind someone else's first refusal.
$LOAD_PATH.unshift File.expand_path("ze0/lib", Dir.pwd)
require "ze0"

files = ARGV.flat_map { |glob| Dir[glob] }.sort
handled = File.read("ze0/lib/ze0/lower.rb").scan(/Prism::(\w+Node)/).flatten.uniq

refusals = Hash.new { |h, k| h[k] = [] }
nodes = Hash.new { |h, k| h[k] = [] }
clean = 0
crashed = []

files.each do |path|
  source = begin
    File.read(path)
  rescue StandardError
    next
  end
  result = Prism.parse(source, filepath: path)
  next unless result.errors.empty?

  walk = lambda do |node|
    name = node.class.name.to_s.sub("Prism::", "")
    nodes[name] << path unless handled.include?(name)
    node.compact_child_nodes.each { |c| walk.call(c) }
  end
  walk.call(result.value)

  begin
    Ze0.compile(source, path)
    clean += 1
  rescue Ze0::Unsupported => e
    # Drop the line number; the shape is what is being counted.
    refusals[e.message.sub(/\Aline \d+: /, "").sub(" is not in ze0's subset", "")] << path
  rescue StandardError, SystemStackError, NoMemoryError => e
    crashed << "#{path}: #{e.class}: #{e.message.lines.first.to_s.strip[0, 90]}"
  end
end

puts "files: #{files.size}  compiled: #{clean}  refused: #{files.size - clean - crashed.size}  crashed: #{crashed.size}"
puts
puts "== first refusal, by count =="
refusals.sort_by { |_, v| -v.size }.each do |what, where|
  puts format("%5d  %-58s %s", where.size, what[0, 58], where.first.sub("#{Dir.pwd}/", ""))
end
puts
puts "== Prism node kinds ze0's lowering never names =="
nodes.sort_by { |_, v| -v.size }.each do |name, where|
  puts format("%5d  %-34s in %d file(s)  %s", where.size, name, where.uniq.size,
              where.first.sub("#{Dir.pwd}/", ""))
end
unless crashed.empty?
  puts
  puts "== crashed rather than refused (each is a bug) =="
  puts crashed.first(40)
end
