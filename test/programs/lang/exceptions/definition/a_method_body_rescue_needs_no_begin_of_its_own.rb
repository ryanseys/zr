class Worker
  def safe
    raise "oops"
  rescue => e
    "handled: #{e.send(:message)}"
  end
end
puts Worker.new.safe

