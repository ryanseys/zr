class Box
  private

  def secret
    "shh"
  end
end

puts Box.new.send(:secret)
