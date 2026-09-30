class Named
  def initialize(n)
    @n = n
  end

  def to_s
    "Named<#{@n}>"
  end

  def inspect
    "#<Named n=#{@n}>"
  end
end

n = Named.new(7)
puts n
puts "in a string: #{n}"
p n
