# RubyVM::AbstractSyntaxTree over prism with parse.y taxonomy: the tree
# shapes below are the oracle's own dumps (type, location, children) for the
# tier of constructs zr maps faithfully. node_id values are zr-numbered
# (prism's ids are parse-internal), so only their presence is pinned.
$stderr.reopen(IO::NULL)

def dump(n)
  return "nil" if n.nil?
  unless n.is_a?(RubyVM::AbstractSyntaxTree::Node)
    return n.inspect
  end
  kids = n.children.map { |c| dump(c) }
  "(#{n.type} [#{n.first_lineno}:#{n.first_column}-#{n.last_lineno}:#{n.last_column}] #{kids.join(' ')})"
end

# ---- YJIT, never enabled.
y = RubyVM::YJIT
p [y.enabled?, y.stats_enabled?, y.log_enabled?, y.trace_exit_locations_enabled?]
p [y.runtime_stats, y.exit_locations, y.log]
begin
  y.dump_exit_locations("/tmp/x")
rescue ArgumentError => e
  p [e.class, e.message]
end
p [y.code_gc, y.reset_stats!]

