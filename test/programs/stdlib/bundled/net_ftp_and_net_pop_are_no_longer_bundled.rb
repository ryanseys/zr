# ruby 4.1 no longer bundles net-ftp and net-pop: a require of either is
# a LoadError. tsort, a default gem before, is now a bundled gem, and
# loads as before.
%w[net/ftp net/pop].each do |feature|
  begin
    require feature
    p [feature, :loaded]
  rescue LoadError => e
    p [feature, e.class, e.message, e.path]
  end
end

require "tsort"
graph = { 1 => [2, 3], 2 => [3], 3 => [], 4 => [] }
each_node = ->(&b) { graph.each_key(&b) }
each_child = ->(n, &b) { graph[n].each(&b) }
p TSort.tsort(each_node, each_child)
p TSort.strongly_connected_components(each_node, each_child)
