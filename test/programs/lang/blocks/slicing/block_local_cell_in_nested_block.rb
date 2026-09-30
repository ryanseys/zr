# A local declared in a block that sits inside another block, and captured by a
# third. Each iteration of the middle block gets a fresh local.
Section = Struct.new(:statements)

sections = [Section.new(["Order", "Chaos"])]

sections.each do |section|
  ["a.rb", "b.rb"].each do |path|
    terms = {}
    section.statements.each { |term| terms[term] = path }
    p terms
  end
end

# Each iteration has its own binding. Procs made in the inner block must each
# see their own `seen`, not the last iteration's.
made = []
[1, 2].each do |outer|
  [10, 20].each do |inner|
    seen = []
    seen << (outer * inner)
    made << proc { seen }
  end
end
p made.map { |pr| pr.call }

# The same shape one level deeper, and with a non-container cell.
counts = []
[[1, 2], [3]].each do |group|
  group.each do |n|
    total = 0
    [n, n].each { |x| total += x }
    counts << proc { total }
  end
end
p counts.map { |pr| pr.call }
