import gleam/bit_array

pub type RespData {
  String(content: String)
}

pub type ParseError {
  UnexpectedInput(got: BitArray)
  InvalidUnicode
  NotEnoughInput
}

pub type Parsed {
  Parsed(data: RespData, remaining_input: BitArray)
}

pub fn parse(input: BitArray) -> Result(Parsed, ParseError) {
  case input {
    <<"+":utf8, rest:bits>> -> parse_simple_string(rest, <<>>)
    input -> Error(UnexpectedInput(input))
  }
}

fn parse_simple_string(
  input: BitArray,
  content: BitArray,
) -> Result(Parsed, ParseError) {
  case input {
    <<>> -> Error(NotEnoughInput)

    <<"\r\n":utf8, input:bits>> -> {
      case bit_array.to_string(content) {
        Ok(content) -> Ok(Parsed(String(content), input))
        Error(_) -> Error(InvalidUnicode)
      }
    }
    <<c, input:bits>> -> {
      parse_simple_string(input, <<content:bits, c>>)
    }
    input -> Error(UnexpectedInput(got: input))
  }
}
