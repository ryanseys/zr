require "ripper"

def t(label)
  print label, ": "
  p yield
rescue StandardError => e
  puts "#{e.class}: #{e.message}"
end

# The file name: "(ripper)" by default, else a frozen copy of the String.
t("default") { [Ripper.new("").filename, Ripper.new("").filename.frozen?] }
t("nil name") { Ripper.new("", nil).filename }
name = +"ripper"
kept = Ripper.new("", name)
name.clear
t("copy") { [kept.filename, kept.filename.frozen?] }
path = Object.new
def path.to_str = "via_to_str"
t("to_str name") { Ripper.new("", path).filename }
t("symbol name") { Ripper.new("", :sym) }
t("nul name") { Ripper.new("", "a\0b") }

# The line: a C int.
t("lineno") { Ripper.sexp_raw("x", "f", 5).inspect.include?("5") }
t("string lineno") { Ripper.new("", "f", "3") }
t("float lineno") { Ripper.new("1", "f", 2.9).parse }
t("big lineno") { Ripper.new("", "f", 2**40) }

# The source: a String (to_str too), or an input whose gets is read when
# the parse starts.
src = Object.new
def src.to_str = "1 + 1"
t("to_str source") { Ripper.sexp(src) }
t("integer source") { Ripper.new(1) }

Lines = Struct.new(:lines, :calls) do
  def gets
    self.calls += 1
    lines.shift
  end
end
input = Lines.new(["a = 1\n", "a + 2\n"], 0)
reader = Ripper.new(input)
t("unread before parse") { input.calls }
t("sexp of gets") { Ripper::SexpBuilder.new(Lines.new(["a = 1\n", "a\n"], 0)).parse }
t("parse") { reader.parse }
t("read at parse") { input.calls }
t("second parse") { reader.parse }
t("gets of 0") { Ripper.new(Lines.new([0], 0)).parse }
t("gets of a symbol") { Ripper.new(Lines.new(["a\n", :b], 0)).parse }
t("new of a bad gets") { Ripper.new(Lines.new([0], 0)).class }

IO.pipe do |r, w|
  w.write("[1,\n 2]\n")
  w.close
  t("io source") { Ripper.sexp(r) }
end

# An invalid source whose last token is not prism's end of input gives
# no on_eof event to a builder.
erb = <<~ERB
  <%- @title = 'x' -%>
  <div class="a"><%= @b %></div>
ERB
t("erb sexp") { Ripper.sexp(erb) }
t("erb sexp_raw") { Ripper.sexp_raw(erb) }
