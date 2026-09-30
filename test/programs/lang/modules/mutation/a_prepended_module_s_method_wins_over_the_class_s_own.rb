class Animal
  def speak
    "generic"
  end
end

module Tagged
  def tag
    "base(#{super})"
  end
end

class Widget
  include Tagged
  def tag
    "widget"
  end
end
puts Widget.new.tag

