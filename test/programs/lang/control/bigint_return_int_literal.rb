# A method can return a Bignum (an accumulator multiply under
# --int-overflow=promote), and its early guard returns a plain Integer
# literal. The caller compares both kinds of result correctly (as in
# tep's proxy retry loop).
class RetryPolicy
  attr_accessor :base_backoff_ms, :backoff_multiplier
  def initialize
    @base_backoff_ms = 0
    @backoff_multiplier = 2
  end
  def backoff_for(attempt)
    if @base_backoff_ms <= 0
      return 0
    end
    d = @base_backoff_ms
    i = 0
    while i < attempt
      d = d * @backoff_multiplier
      i += 1
    end
    d
  end
end

class Base
  def retry_policy
    RetryPolicy.new
  end
  def handle(attempt)
    policy = retry_policy
    backoff = policy.backoff_for(attempt)
    if backoff > 0
      puts "sleep"
      puts backoff
    else
      puts "no sleep"
    end
  end
end

class Sub < Base
  def retry_policy
    p = RetryPolicy.new
    p.base_backoff_ms = 100
    p
  end
end

Base.new.handle(1)   # zero base -> the early `return 0` path
Sub.new.handle(0)    # 100 * 2**0
Sub.new.handle(3)    # 100 * 2**3
Sub.new.handle(62)   # overflows int64: the result is a Bignum
