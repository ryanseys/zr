class Risky
  def check
    raise "plain string error"
  end
end
Risky.new.check
