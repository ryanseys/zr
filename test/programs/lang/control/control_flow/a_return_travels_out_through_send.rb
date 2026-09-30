class Relay
  def go(&b)
    begin
      __send__(:inner, &b)
    rescue StandardError
      :r
    end
    :fell
  end
  def inner = yield(:through_send)
end
def c9; Relay.new.go { |v| return v }; :no; end
p c9

