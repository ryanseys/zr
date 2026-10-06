# InstructionSequence.compile takes its options as keywords or as a last
# Hash; frozen_string_literal sets the literals, and a magic comment of
# the source wins. The first line stays the one given.
p RubyVM::InstructionSequence.compile("'a'.frozen?", frozen_string_literal: true).eval
p RubyVM::InstructionSequence.compile("'a'.frozen?", frozen_string_literal: false).eval
p RubyVM::InstructionSequence.compile("# frozen_string_literal: false\n'a'.frozen?", frozen_string_literal: true).eval
p RubyVM::InstructionSequence.compile("__LINE__", "f.rb", "f.rb", 7, frozen_string_literal: true).eval
p RubyVM::InstructionSequence.compile("'a'.frozen?", nil, nil, 1, { frozen_string_literal: true }).eval
