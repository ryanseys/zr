# RubyVM::DEFAULT_PARAMS takes each stack size from its environment
# variable as ruby starts: at least the minimum, rounded up to a page.
p RubyVM::DEFAULT_PARAMS
p RubyVM::DEFAULT_PARAMS.frozen?
