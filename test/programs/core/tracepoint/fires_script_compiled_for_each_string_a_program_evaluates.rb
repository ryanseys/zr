# `:script_compiled` fires once a string of Ruby has compiled and before
# it runs. `eval_script` is the string; `instruction_sequence` carries
# what the code answers to -- the name, the label and the first line
# `rb_iseqw_new` would give it.
#
# The event stands where the program called the eval form, because
# CRuby's form is a C frame with no place of its own and
# rb_tracearg_path walks out to the nearest Ruby one. The name, the
# owner and `self` come from the form itself, so `1.instance_eval`
# answers 1 and BasicObject, and `module_eval` answers the name it was
# called by rather than the one `class_eval` was defined under.
seen = []
tp = TracePoint.new(:script_compiled) do |t|
  i = t.instruction_sequence
  seen << [t.lineno, t.method_id, t.defined_class.to_s, t.self.inspect,
           t.eval_script, i.path, i.label, i.first_lineno]
end

tp.enable do
  eval("1 + 1")
  1.instance_eval("2")
  String.class_eval("3")
  String.module_eval("4")
  eval("6", nil, "given.rb", 40)
end

seen.each { |row| p row }
