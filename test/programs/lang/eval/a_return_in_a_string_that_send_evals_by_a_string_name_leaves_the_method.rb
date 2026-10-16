# send and method take the method's name as a String as well as a
# Symbol, so a return in a string that they eval leaves the method that
# holds the call.
# rubocop:disable Performance/StringIdentifierArgument -- the String names are what this tests
def by_send
  send("eval", "return :from_send")
  :after
end

def by_method
  method("eval").call("return :from_method")
  :after
end

def by_instance_eval
  [1].each { |x| x.send("instance_eval", "return :from_instance_eval") }
  :after
end

p by_send, by_method, by_instance_eval
# rubocop:enable Performance/StringIdentifierArgument
