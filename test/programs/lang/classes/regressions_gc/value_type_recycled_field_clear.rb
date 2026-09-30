class T_value_type_recycled_field_clear_NameTag
  attr_reader :text

  def initialize(text)
    @text = text
  end
end

class T_value_type_recycled_field_clear_Holder
  attr_reader :tag, :junk

  def initialize(tag)
    @junk = []
    @tag = tag
  end
end

i = 0
while i < 3000
  T_value_type_recycled_field_clear_Holder.new(T_value_type_recycled_field_clear_NameTag.new("old" + i.to_s))
  i = i + 1
end

junk = []
i = 0
while i < 5000
  junk << "garbage" + i.to_s
  i = i + 1
end

holder = nil
i = 0
while i < 3000
  holder = T_value_type_recycled_field_clear_Holder.new(T_value_type_recycled_field_clear_NameTag.new("new" + i.to_s))
  i = i + 1
end

puts holder.tag.text
