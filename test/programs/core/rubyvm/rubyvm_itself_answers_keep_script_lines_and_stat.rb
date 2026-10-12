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

# ---- RubyVM itself.
p RubyVM.singleton_methods(false).sort
p RubyVM.constants.sort - %i[YJIT ZJIT] # less the JITs that the build has
p RubyVM.keep_script_lines
RubyVM.keep_script_lines = true
p RubyVM.keep_script_lines
RubyVM.keep_script_lines = false
p RubyVM.stat.keys.sort
p RubyVM.stat.values.all? { |v| v.is_a?(Integer) }
p RubyVM.stat(:constant_cache_invalidations).is_a?(Integer)
begin
  RubyVM.stat(:bogus)
rescue ArgumentError => e
  p [e.class, e.message]
end
p [RubyVM::OPTS.class, RubyVM::OPTS.frozen?]
p [RubyVM::INSTRUCTION_NAMES.class, RubyVM::INSTRUCTION_NAMES.frozen?]
p [RubyVM::DEFAULT_PARAMS.keys.sort, RubyVM::DEFAULT_PARAMS.frozen?]

