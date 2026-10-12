# ruby makes error_highlight, did_you_mean and syntax_suggest autoloads
# at boot. The first call of Exception#detailed_message loads them, and
# their decorators then apply to that same call.
loaded = -> { $LOADED_FEATURES.count { |path| path.match?(%r{/(error_highlight|did_you_mean|syntax_suggest)(/[^/]+)?\.rb\z}) } }

p %i[ErrorHighlight DidYouMean SyntaxSuggest].map { |name| Object.autoload?(name) }
p loaded.call
p defined?(DidYouMean)
p loaded.call

# A plain rescue does not display the error, so nothing loads.
begin
  nope
rescue NameError => e
  p e.message
end
p loaded.call

# $! stays the error that is displayed.
begin
  putz
rescue NameError => e
  text = e.detailed_message
  p text.include?("Did you mean?")
  p $!.equal?(e)
end
p loaded.call.positive?
p %i[ErrorHighlight DidYouMean SyntaxSuggest].map { |name| Object.autoload?(name) }

# The next display decorates as well.
begin
  [].fetchh
rescue NoMethodError => e
  p e.detailed_message.include?("Did you mean?  fetch")
end
