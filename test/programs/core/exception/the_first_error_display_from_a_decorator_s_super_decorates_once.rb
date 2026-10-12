# When the first detailed_message call comes through super from a
# decorator above Exception's own method, ruby loads the libraries but
# does not dispatch again: the caller decorates the result, once.
class LoudError < NameError
  def detailed_message(**)
    "loud: #{super}"
  end
end

begin
  raise LoudError.new("missing thing", :thing)
rescue LoudError => e
  p e.detailed_message
  p e.detailed_message
end
p Object.autoload?(:DidYouMean)
