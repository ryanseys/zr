names = RubyVM::INSTRUCTION_NAMES
p names.size
p names.first(5)
p names.last(3)
p names.frozen?, names.all?(String), names.all?(&:frozen?)
p names.index("opt_send_without_block") > names.index("send")
p names.include?("trace_nop"), names.uniq.size == names.size
p RubyVM::OPTS
