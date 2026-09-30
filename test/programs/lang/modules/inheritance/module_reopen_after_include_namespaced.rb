# A module is forward-declared empty, included by a class nested
# inside another module, and then reopened with method
# definitions. The class sees the late-defined methods, as a
# top-level class does. A reopen later in source order than the
# include still counts.

class TestBase
end

module RequestDispatch
end

module ActionDispatch
  class IntegrationTest < TestBase
    include RequestDispatch
  end
end

module RequestDispatch
  def post(path); "post:" + path; end
end

puts ActionDispatch::IntegrationTest.new.post("/x")
