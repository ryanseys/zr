require "racc/parser"
# racc loads its C core: the parser runs it, and names what it defines.
p Racc::Parser::Racc_Runtime_Type, Racc::Parser::Racc_Main_Parsing_Routine, Racc::Parser::Racc_YY_Parse_Method
p Racc::Parser::Racc_Runtime_Core_Version_C == Racc::VERSION, Racc::Parser::Racc_Runtime_Core_Version_C.frozen?
p Racc.constants(false).sort
p (Racc::CparseParams.new rescue $!)
