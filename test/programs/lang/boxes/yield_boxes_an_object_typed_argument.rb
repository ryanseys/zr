# `yield self` passes the object to the block, and a send on it works.

class Builder
  def run
    yield self
  end
  def ping = "pong"
end
Builder.new.run { |b| puts b.send(:ping) }
