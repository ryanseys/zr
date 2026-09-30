class Sep
  def to_str
    "-"
  end
end

class Idx
  def to_int
    1
  end
end

def err
  yield
rescue StandardError => e
  [e.class, e.message]
end

class Sep
  def to_str
    "-"
  end
end

class Idx
  def to_int
    1
  end
end

def err
  yield
rescue StandardError => e
  [e.class, e.message]
end

p "a-b-".chomp(Sep.new)
s = String.new("a-b")
p [s.chomp!(Sep.new), s]
p "a".ljust(4, Sep.new)
p "a".rjust(4, Sep.new)
p "a".center(5, Sep.new)
p "a-b".index(Sep.new, 0)
p "a-b-".rindex(Sep.new)
p "a-b-".rindex(Sep.new, 2)
p "\xff".scrub(Sep.new) == "-"
p String.new("\xff").scrub!(Sep.new) == "-"
p "a-b-c".split(Sep.new, 2)
p "a-b-c".split(Sep.new)
p "a".upto(Sep.new).to_a.size
class Fmt
  def to_str
    "a"
  end
end
p "ab".unpack1(Fmt.new)
p String.new("abc").bytesplice(0, 1, Sep.new)
p Time.utc(2000).strftime(Sep.new)
p String.new(Sep.new)
p Regexp.escape(Sep.new)
p format(Sep.new)
p sprintf(Sep.new)
ENV["SPINEL_SLOT"] = "v"
class Key
  def to_str
    "SPINEL_SLOT"
  end
end
p ENV[Key.new]
p ENV.key?(Key.new)
p ENV.store(Key.new, "w")
p ENV.delete(Key.new)
class Cmd
  def to_str
    "true"
  end
end
p system(Cmd.new)
p err { "abc".rindex(1) }
p err { "abc".ljust(4, 1) }
p err { "a-b".chomp(1) }
p err { "abc".split(1) }
p err { format(1) }
p err { Time.utc(2000).strftime(1) }
p err { Regexp.escape(1) }
p err { String.new(1) }

