# An eval compiles its string here with a compiler in Ruby, over prism,
# which the program carries. Its constants, Ze0 and Prism, are then in
# Object.constants and answer defined?, where ruby has neither until a
# require of prism.
eval "1"
p Object.constants.include?(:Prism), defined?(Prism)
p Object.constants.include?(:Ze0), defined?(Ze0)

__END__
false
nil
false
nil
