# A module is reopened after a namespaced class includes it. The reopened
# method `Dispatch#post` writes `@session ||= ...`. The including class
# `NS::IntegrationTest` gets the method, and the ivar works on its instances.

module Dispatch
end

class Base
end

module NS
  class IntegrationTest < Base
    include Dispatch
  end
end

module Dispatch
  def post(path)
    @session ||= "session-obj"
    puts @session
    puts path
  end
end

NS::IntegrationTest.new.post("/foo")
