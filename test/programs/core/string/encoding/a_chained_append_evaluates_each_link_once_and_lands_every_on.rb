# chained string appends (`s << a << b`) evaluate each link exactly once and
# every append lands on the base. In tail position the inner links do not
# run twice, so the text is not doubled. In value position the base gets
# every append, not only the innermost one.

# tail position, through a mutated parameter (the byref shape)
def emit(buf, label)
  buf << "[" << label << "]"
end

s = +""
emit(s, "ok")
p s
r = emit(s, "go")
p r
p s

# value position: assignment keeps base and result in step
t = +"x"
u = (t << "a" << "b")
p t
p u

# parenthesized links and a longer chain
v = +""
(v << "1") << "2" << "3"
p v

# int argument appends its codepoint character
w = +"y"
w << "-" << 33
p w

# ivar base
class Sink
  def initialize
    @buf = +"<"
  end

  def push(a, b)
    @buf << a << b
  end
end

k = Sink.new
p k.push("m", ">")

# repeated tail chains accumulate (the serializer shape)
def line(out, op, arg)
  out << op << " " << arg << "\n"
end

prog = +""
line(prog, "LOAD", "a")
line(prog, "JUMP", "top")
print prog
