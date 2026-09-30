# Same rule as the private case above -- a runtime NoMethodError.

class Money
  def initialize(amount)
    @amount = amount
  end

  protected

  def amount
    @amount
  end
end

a = Money.new(10)
begin
  a.amount
rescue NoMethodError => e
  puts e.message
end
