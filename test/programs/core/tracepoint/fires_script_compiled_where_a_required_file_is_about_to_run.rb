# A file a require reached fires the same event: `eval_script` is nil,
# because no string was compiled, and the sequence answers to the file
# and carries `<top (required)>`. ruby fires it where the file compiles;
# this runtime compiled it before the program began, so it fires at the
# one moment the program can see, which is the file's first run.
seen = []
tp = TracePoint.new(:script_compiled) do |t|
  i = t.instruction_sequence
  seen << [t.lineno, t.method_id, t.defined_class.to_s, t.self.inspect,
           t.eval_script, File.basename(i.path), i.label, i.first_lineno]
end

def load_it
  require_relative "script_compiled/loaded"
end

tp.enable { load_it }
p LOADED_HERE
seen.each { |row| p row }
