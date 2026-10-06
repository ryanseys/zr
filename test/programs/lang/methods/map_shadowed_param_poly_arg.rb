# A value-position map whose block param feeds a poly-widened callee param.
# The param's scope-local rides the fixpoint to poly (its array's element type
# settles late), and in the map body it is a String. A read of it as a call
# ARGUMENT also gets the correct type, so the callee gets the right value.

class Reader
  def initialize(data)
    @data = data
    @pos = 0
  end

  def read_hash
    s = @data[@pos, 4]
    @pos += 4
    s
  end
end

class Proof
  attr_reader :fri_roots

  def initialize(fri_roots)
    @fri_roots = fri_roots
  end
end

class Transcript
  def initialize
    @n = 0
  end

  def absorb(label, data)
    @n += 1
  end

  def challenge
    [@n, @n * 10]
  end
end

def deserialize(data)
  reader = Reader.new(data)
  roots = Array.new(2) { reader.read_hash }
  Proof.new(roots)
end

def verify(proof, transcript)
  proof.fri_roots.map do |root|
    transcript.absorb("fri_root", root)
    transcript.challenge
  end
end

proof = deserialize("aaaabbbb")
transcript = Transcript.new
transcript.absorb("init", 42)
p verify(proof, transcript)
p proof.fri_roots
