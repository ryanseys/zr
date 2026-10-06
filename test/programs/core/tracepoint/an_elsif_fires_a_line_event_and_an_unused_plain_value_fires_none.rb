# An `elsif` that starts a line fires its :line event before its
# predicate. A statement whose value nothing uses and that compiles to no
# instruction (a literal, a local, a static Array, a Hash or Range of
# such values) fires none, as CRuby's compiler drops it.
class C
  @@cv = 1
  def f(a)
    1
    "s"
    "i#{a}"
    :sym
    nil
    self
    a
    @iv
    @@cv
    [1]
    [a]
    [1, [2, :x]]
    {a: a}
    {"k" => [1]}
    1..a
    (1)
    defined?(zz)
    __FILE__
    -> {}
    x = 1
    x
    $g
    if a
      3
    elsif !a
      z = 4
    elsif a.nil?
      5
    end
    if a then 1 elsif a then 2 else 3 end
    y = if !a then 1
        elsif a then 2
        end
    2
  end
end

base = __LINE__
lines = []
TracePoint.new(:line) { |tp| lines << tp.lineno if tp.path == __FILE__ }.enable { C.new.f(nil) }
p lines.map { |l| l < base ? l : l - base }
