# Exceptions raise and rescue at nested depths that go up and down, with
# allocation and collection between them. A rescued exception that nothing
# refers to any more must not stay reachable, and later exceptions at the
# same depth must work.

class MissingTemplate < StandardError; end

def churn(i)
  s = +""
  10.times { |j| s << "<input name=\"f#{i}_#{j}\" value=\"_csrf_token\">" }
  s.length
end

def deep(n, i)
  return (raise MissingTemplate, "t#{i}") if n == 0
  begin
    deep(n - 1, i)
  rescue MissingTemplate => e
    churn(i)
    raise e if n > 1
    e.message.length
  end
end

total = 0
2000.times do |i|
  d = (i % 3) + 1
  begin
    total += deep(d, i)
  rescue MissingTemplate
    total += 1
  end
  total += churn(i)
end
p total > 0
