# `extend M` written in a REOPENING of the class: an `extend` in any body of
# the class adds the module's methods, not only an `extend` in the first body.
class Win
  def self.shown?
    false
  end

  module ClassMethods
    def check
      shown? ? 'yes' : 'no'
    end

    def viewport_width
      100
    end
  end
end

class Win
  extend ClassMethods
end

puts Win.check
puts Win.viewport_width

# the same module extended in the original body still works
class Dlg
  def self.open?
    true
  end

  module CM
    def state
      open? ? 'open' : 'shut'
    end
  end

  extend CM
end

puts Dlg.state
