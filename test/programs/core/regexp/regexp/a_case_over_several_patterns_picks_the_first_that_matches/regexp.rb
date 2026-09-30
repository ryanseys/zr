
m = "hello world".match(/(\w+) (\w+)/)

named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
h = named.named_captures


multiline_str = "abc\ndef"

r = /abc/x




count = 0
"one two three".gsub(/\w+/) { |w| count += 1; w }


class Classifier
  def classify(x)
    case x
    when /^\d+$/
      "number"
    when /^[a-z]+$/
      "lower"
    else
      "other"
    end
  end

  def classify_in(x)
    case x
    in /^\d+$/
      "number"
    in /^[a-z]+$/
      "lower"
    else
      "other"
    end
  end
end
classifier = Classifier.new
puts classifier.classify("123")
puts classifier.classify("abc")
puts classifier.classify("ABC")
puts classifier.classify_in("123")
puts classifier.classify_in("abc")

