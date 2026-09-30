# Each inner top-level def has a per-test prefix, so its name is
# unique across the tests.


def t_osp_parse(source, file_path = nil)
  if file_path
    puts file_path.length
  else
    puts source.length
  end
end

def t_optional_string_param_method
  t_osp_parse("abc", "name.rb")
  t_osp_parse("abc")
  t_osp_parse("longer", "another_name.rb")
end
t_optional_string_param_method
