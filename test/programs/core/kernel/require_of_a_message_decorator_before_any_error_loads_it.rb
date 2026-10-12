# Before the first error display, a require of a decorator's library
# reads it, so the require returns true and the autoload ends.
p require("did_you_mean")
p require("did_you_mean")
p Object.autoload?(:DidYouMean)
p Object.autoload?(:ErrorHighlight)
p require("error_highlight")
p Object.autoload?(:ErrorHighlight)
begin
  putz
rescue NameError => e
  p e.detailed_message.include?("Did you mean?")
end
