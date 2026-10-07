# A statement's :line event reports the line of the first instruction
# that CRuby compiles for it: a write's value, a call's receiver, the
# first element of an Array or Hash that is not one static value, the
# code of an interpolated heredoc, and the first `when` of a `case` with
# no subject. A literal condition compiles to its chosen branch alone.
# A statement whose first instruction is that of the statement around
# it shares its event: the line fires once.
def lines_of
  lines = []
  TracePoint.new(:line) { |tp| lines << tp.lineno if tp.path == __FILE__ }.enable { yield }
  lines
end

def value_below
  x =
    1.to_s
  x
end

def array_below
  y = [
    1.to_s,
    2
  ]
  y
end

def static_array
  z = [
    1,
    2
  ]
  z
end

def hash_below
  w = {
    a: 1.to_s,
    b: 2
  }
  w
end

def static_first_pair
  v = {
    "a" => nil,
    "b" => 2.to_s
  }
  v
end

def plain_heredoc
  u = <<~TEXT
    plain
      indented
  TEXT
  u
end

def heredoc_code
  t = <<~TEXT
    #{1.to_s}
  TEXT
  t
end

def receiver_below
  s = !
    nil.to_a
  s
end

def no_subject(a)
  case
  when a == 1
    :one
  when a == 2
    :two
  end
end

def literal_condition
  r = if true
    1.to_s
  else
    2.to_s
  end
  r
end

def literal_false_unused
  :before
  1.to_s if false
  :after.to_s
end

def literal_statement
  if true
    1.to_s
  end
end

def begin_value
  b = begin
    1.to_s
  end
  b
end

def parens_value
  q = (
    1.to_s
  )
  q
end

def case_true(v)
  c = case
      when true
        v.to_s
      end
  c
end

def if_in_array
  a = [
    if true
      1.to_s
    end
  ]
  a
end

p lines_of { value_below }
p lines_of { array_below }
p lines_of { static_array }
p lines_of { hash_below }
p lines_of { static_first_pair }
p lines_of { plain_heredoc }
p lines_of { heredoc_code }
p lines_of { receiver_below }
p lines_of { no_subject(1) }
p lines_of { no_subject(2) }
p lines_of { literal_condition }
p lines_of { literal_false_unused }
p lines_of { literal_statement }
p lines_of { begin_value }
p lines_of { parens_value }
p lines_of { case_true(1) }
p lines_of { if_in_array }
