# Process.warmup loads error_highlight, did_you_mean and syntax_suggest
# now, not at the first error display.
p Object.autoload?(:ErrorHighlight)
p Process.warmup
p %i[ErrorHighlight DidYouMean SyntaxSuggest].map { |name| Object.autoload?(name) }
p $LOADED_FEATURES.any? { |path| path.end_with?("/did_you_mean.rb") }
p Process.warmup
