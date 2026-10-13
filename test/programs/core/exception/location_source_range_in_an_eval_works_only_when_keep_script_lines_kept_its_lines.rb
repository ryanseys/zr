# Thread::Backtrace::Location#source_range in code that an eval compiled:
# ruby finds the node again only when RubyVM.keep_script_lines was on
# when the eval compiled. Each eval keeps its own ranges, so two evals
# with one file name give their own nodes.
def where = caller_locations(1, 1).first

def show(label)
  range = yield
  return p [label, range] unless range.is_a?(Ruby::SourceRange)

  p [label, range, range.path, range.absolute_path, range.start_line, range.start_column, range.end_line, range.end_column]
rescue => e
  p [label, e.class, e.message]
end

show(:plain) { eval("where", nil, "plain.rb").source_range }
before = eval("where", nil, "before.rb")

RubyVM.keep_script_lines = true
show(:second_line) { eval("x = 1\n  where", nil, "second.rb").source_range }
show(:named) { binding.eval("where", "named.rb", 10).source_range }
show(:same_name_other_code) { binding.eval("[0,\n where]", "named.rb", 10).last.source_range }
show(:instance_eval) { Object.new.instance_eval("  where", "instance.rb", 3).source_range }
show(:class_eval) { Class.new.class_eval("x = 1; where", "class.rb").source_range }
show(:nested) { eval("eval('where', nil, \"inner.rb\")", nil, "outer.rb").source_range }
show(:nested_outer) { eval("[where, eval('1')]", nil, "outer.rb").first.source_range }
show(:in_a_block) { eval("[1].map { where }", nil, "block.rb").first.source_range }
show(:in_a_def) { eval("def from_eval = where\nfrom_eval", nil, "def.rb").source_range }
show(:compiled_before) { before.source_range }
error = begin
  eval("\n\n  nil.upcase", nil, "error.rb")
rescue NoMethodError => e
  e
end
show(:raised) { error.backtrace_locations.first.source_range }
show(:node_id) { RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location(eval("where", nil, "id.rb")).class }
kept = eval("where", nil, "kept.rb")
loop_kept = 2.times.map { eval("where", nil, "loop.rb") }

RubyVM.keep_script_lines = false
show(:kept_then_off) { kept.source_range }
show(:same_code_again) { eval("where", nil, "kept.rb").source_range }
show(:loop) { loop_kept.map { _1.source_range.inspect }.uniq }
show(:proc_after) { eval("proc { 1 }", nil, "proc.rb").source_range }
