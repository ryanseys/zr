# full_message calls detailed_message, so it also loads the decorators
# at its first call, with the highlight that it was given.
p Object.autoload?(:DidYouMean)
begin
  [1].frist
rescue NoMethodError => e
  puts e.full_message(highlight: false, order: :top).lines.grep(/Did you mean/)
  puts e.detailed_message(highlight: true).lines.first.include?("\e[1m")
end
p Object.autoload?(:DidYouMean)
