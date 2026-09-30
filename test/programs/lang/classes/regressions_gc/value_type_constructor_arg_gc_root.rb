class T_value_type_constructor_arg_gc_root_NameTag
  attr_reader :present, :text

  def initialize(present, text)
    @present = present
    @text = text
  end
end

class T_value_type_constructor_arg_gc_root_Payload
end

class T_value_type_constructor_arg_gc_root_Wrapper
  attr_reader :tag, :payload

  def initialize(tag, payload)
    @tag = tag
    @payload = payload
  end

  def self.for_tag(tag)
    junk = []
    i = 0
    while i < 50
      junk << "junk" + i.to_s
      i = i + 1
    end

    T_value_type_constructor_arg_gc_root_Wrapper.new(tag, T_value_type_constructor_arg_gc_root_Payload.new)
  end
end

wrapper = nil
i = 0
while i < 2000
  wrapper = T_value_type_constructor_arg_gc_root_Wrapper.for_tag(T_value_type_constructor_arg_gc_root_NameTag.new(1, "label" + i.to_s))
  i = i + 1
end

puts wrapper.tag.text
