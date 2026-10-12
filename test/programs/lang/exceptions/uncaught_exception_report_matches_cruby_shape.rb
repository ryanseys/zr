# The top-level report: innermost frame heads the message line, outer
# frames follow tab-indented -- verbatim ruby output (as `-e`).

def inner; raise "boom"; end
def outer; inner; end
outer
