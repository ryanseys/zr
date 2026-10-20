# frozen_string_literal: true

# Derived from libyaml 0.2.5 (MIT); see THIRD_PARTY_NOTICES.md.
#
# The public types of libyaml 0.2.5 (include/yaml.h): the enumerations,
# the marks, the tokens and the events that the reader, the scanner, the
# parser and the emitter pass between them.
#
# C strings become binary Ruby strings. A NULL pointer is nil, and an
# empty C string is "".
module Psych
  module LibYAML
    VERSION = [0, 2, 5].freeze

    # yaml_encoding_t
    ANY_ENCODING = 0
    UTF8_ENCODING = 1
    UTF16LE_ENCODING = 2
    UTF16BE_ENCODING = 3

    # yaml_break_t
    ANY_BREAK = 0
    CR_BREAK = 1
    LN_BREAK = 2
    CRLN_BREAK = 3

    # yaml_error_type_t
    NO_ERROR = 0
    MEMORY_ERROR = 1
    READER_ERROR = 2
    SCANNER_ERROR = 3
    PARSER_ERROR = 4
    COMPOSER_ERROR = 5
    WRITER_ERROR = 6
    EMITTER_ERROR = 7

    # yaml_scalar_style_t
    ANY_SCALAR_STYLE = 0
    PLAIN_SCALAR_STYLE = 1
    SINGLE_QUOTED_SCALAR_STYLE = 2
    DOUBLE_QUOTED_SCALAR_STYLE = 3
    LITERAL_SCALAR_STYLE = 4
    FOLDED_SCALAR_STYLE = 5

    # yaml_sequence_style_t
    ANY_SEQUENCE_STYLE = 0
    BLOCK_SEQUENCE_STYLE = 1
    FLOW_SEQUENCE_STYLE = 2

    # yaml_mapping_style_t
    ANY_MAPPING_STYLE = 0
    BLOCK_MAPPING_STYLE = 1
    FLOW_MAPPING_STYLE = 2

    # yaml_token_type_t
    NO_TOKEN = 0
    STREAM_START_TOKEN = 1
    STREAM_END_TOKEN = 2
    VERSION_DIRECTIVE_TOKEN = 3
    TAG_DIRECTIVE_TOKEN = 4
    DOCUMENT_START_TOKEN = 5
    DOCUMENT_END_TOKEN = 6
    BLOCK_SEQUENCE_START_TOKEN = 7
    BLOCK_MAPPING_START_TOKEN = 8
    BLOCK_END_TOKEN = 9
    FLOW_SEQUENCE_START_TOKEN = 10
    FLOW_SEQUENCE_END_TOKEN = 11
    FLOW_MAPPING_START_TOKEN = 12
    FLOW_MAPPING_END_TOKEN = 13
    BLOCK_ENTRY_TOKEN = 14
    FLOW_ENTRY_TOKEN = 15
    KEY_TOKEN = 16
    VALUE_TOKEN = 17
    ALIAS_TOKEN = 18
    ANCHOR_TOKEN = 19
    TAG_TOKEN = 20
    SCALAR_TOKEN = 21

    # yaml_event_type_t
    NO_EVENT = 0
    STREAM_START_EVENT = 1
    STREAM_END_EVENT = 2
    DOCUMENT_START_EVENT = 3
    DOCUMENT_END_EVENT = 4
    ALIAS_EVENT = 5
    SCALAR_EVENT = 6
    SEQUENCE_START_EVENT = 7
    SEQUENCE_END_EVENT = 8
    MAPPING_START_EVENT = 9
    MAPPING_END_EVENT = 10

    # A position in the input: the character index, the line and the
    # column, all from zero. The code treats a mark as a value and never
    # changes one after it makes it.
    Mark = Struct.new(:index, :line, :column)

    ZERO_MARK = Mark.new(0, 0, 0).freeze

    # yaml_version_directive_t
    VersionDirective = Struct.new(:major, :minor)

    # yaml_tag_directive_t
    TagDirective = Struct.new(:handle, :prefix)

    # yaml_token_t. The data union is flat: `value` contains the text of an
    # alias, an anchor or a scalar; `handle` and `suffix` contain a tag;
    # `handle` and `prefix` contain a %TAG directive.
    Token = Struct.new(:type, :start_mark, :end_mark, :encoding, :value, :style,
                       :handle, :suffix, :prefix, :major, :minor)

    # yaml_event_t, with the data union flat as in Token. The implicit
    # flags are true or false.
    Event = Struct.new(:type, :start_mark, :end_mark, :encoding, :version_directive,
                       :tag_directives, :implicit, :anchor, :tag, :value,
                       :plain_implicit, :quoted_implicit, :style)

    # yaml_simple_key_t: a place where a simple key can start. The scanner
    # changes `possible` in place, as libyaml does through its pointer.
    SimpleKey = Struct.new(:possible, :required, :token_number, :mark)

    # The scanner, the parser and the emitter stop at the first error.
    # libyaml returns 0 up through every caller; this port records the
    # error on the object and raises Failure, which the public entry
    # point (Parser#parse, Emitter#emit) turns back into a false result.
    class Failure < StandardError; end
  end
end
