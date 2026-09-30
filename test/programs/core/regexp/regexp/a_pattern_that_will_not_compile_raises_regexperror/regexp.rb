
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

word = "wor"
interpolated = /#{word}ld/

percent = %r{foo/bar}

r2 = /abc/

bad = "("
begin
  invalid = /#{bad}/
  puts "no error"
rescue RegexpError => _e
  puts "regexp error"
end
