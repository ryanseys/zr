# A nil file and path are the defaults, as irb passes them to check
# a line of input.
i = RubyVM::InstructionSequence.compile("1 + 1", nil, nil, 3)
p i.path, i.absolute_path, i.first_lineno, i.eval
