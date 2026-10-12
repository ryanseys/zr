# A program that evals carries a compiler, and the compiler does not load
# the message decorators itself: they stay autoloads until the first
# error display, also an error in eval'd code.
p eval("1 + 1")
p %i[ErrorHighlight DidYouMean SyntaxSuggest].map { |name| Object.autoload?(name) }
p $LOADED_FEATURES.grep(/error_highlight/).size
begin
  eval("[1].frist")
rescue NoMethodError => e
  p e.detailed_message
end
p Object.autoload?(:ErrorHighlight)
