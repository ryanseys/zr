# prism's native half: the parser is linked in, and these are the private
# class methods `prism/zeo.rb` calls. The serialized buffer they answer is
# read back by `Prism::Serialize`, which is ordinary ruby.
module Prism
  class << self
    def version = Primitive.zr_pm_version

    private

    def serialize_parse(source, options) = Primitive.zr_pm_parse(source, options)
    def serialize_parse_comments(source, options) = Primitive.zr_pm_parse_comments(source, options)
    def serialize_lex(source, options) = Primitive.zr_pm_lex(source, options)
    def serialize_parse_lex(source, options) = Primitive.zr_pm_parse_lex(source, options)
    def native_parse_success?(source, options) = Primitive.zr_pm_parse_success(source, options)
  end
end
