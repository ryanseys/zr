# Assert the UNCAUGHT path here (see the `rescue` tests below for the
# caught path): an unhandled `raise MyError` (no explicit message) exits 1 with the
# class's own name as the message (no runtime `self.class` reflection
# needed).

class MyError < StandardError
end
class Box
  def check
    raise MyError
  end
end
Box.new.check
