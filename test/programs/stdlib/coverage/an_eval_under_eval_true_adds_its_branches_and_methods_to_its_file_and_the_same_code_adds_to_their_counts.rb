require "coverage"

# Under `eval: true`, an eval's branches and methods join those of the
# file that it names. Evaluating the same code again adds to the counts
# of the same entries; other code at the same path adds entries.
Coverage.start(eval: true, branches: true, methods: true)

code = <<~RUBY
  def foo(x)
    x ? 1 : 2
  end
RUBY

eval(code, TOPLEVEL_BINDING, "test.rb", 1)
foo(true)
first = Coverage.peek_result["test.rb"]
p first[:branches], first[:methods]

eval(code.sub("foo", "bar"), TOPLEVEL_BINDING, "test.rb", 10)
eval(code, TOPLEVEL_BINDING, "test.rb", 1)
foo(true)
bar(false)
bar(nil)
second = Coverage.peek_result["test.rb"]
p second[:branches], second[:methods].sort_by { |key, _| key.drop(1) }

# The earlier snapshot is its own.
p first[:branches].equal?(second[:branches]), first[:branches].size

# An eval with an `if`, a `case` and a safe call, in a file of its own.
eval(<<~RUBY, TOPLEVEL_BINDING, "other.rb", 1)
  def other(x)
    case x
    when 1 then :one
    else :many
    end
    x&.succ if x
  end
RUBY
other(1)
other(nil)
p Coverage.result["other.rb"][:branches]
