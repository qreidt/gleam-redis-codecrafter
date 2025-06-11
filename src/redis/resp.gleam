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
    <<"$":utf8, rest:bits>> -> parse_bulk_string(rest, 0)
    input -> Error(UnexpectedInput(input))
  }
}

///
/// ## Simple strings
/// 
/// Simple strings are encoded as a plus (+) character, followed by a string. The string mustn't contain a CR (\r) or
/// LF (\n) character and is terminated by CRLF (i.e., \r\n).
/// 
/// Simple strings transmit short, non-binary strings with minimal overhead. For example, many Redis commands reply
/// with just "OK" on success. The encoding of this Simple String is the following 5 bytes:
/// ```
/// +OK\r\n
/// ```
/// 
/// When Redis replies with a simple string, a client library should return to the caller a string value composed of
/// the first character after the + up to the end of the string, excluding the final CRLF bytes.
/// 
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

///
/// ## Bulk strings
/// 
/// A bulk string represents a single binary string. The string can be of any size, but by default, Redis limits it to 512 MB (see the proto-max-bulk-len configuration directive).
/// RESP encodes bulk strings in the following way:
/// 
/// ```
/// $<length>\r\n<data>\r\n
/// ```
/// - The dollar sign ($) as the first byte.
/// - One or more decimal digits (0..9) as the string's length, in bytes, as an unsigned, base-10 value.
/// - The CRLF terminator.
/// - The data.
/// - A final CRLF.
/// 
/// So the string "hello" is encoded as follows:
/// ```
/// $5\r\nhello\r\n
/// ```
/// The empty string's encoding is:
/// ```
/// $0\r\n\r\n
/// ```
/// 
fn parse_bulk_string(input: BitArray, length: Int) -> Result(Parsed, ParseError) {
  case input {
    <<"0":utf8, input:bits>> -> parse_bulk_string(input, length * 10)
    <<"1":utf8, input:bits>> -> parse_bulk_string(input, 1 + length * 10)
    <<"2":utf8, input:bits>> -> parse_bulk_string(input, 2 + length * 10)
    <<"3":utf8, input:bits>> -> parse_bulk_string(input, 3 + length * 10)
    <<"4":utf8, input:bits>> -> parse_bulk_string(input, 4 + length * 10)
    <<"5":utf8, input:bits>> -> parse_bulk_string(input, 5 + length * 10)
    <<"6":utf8, input:bits>> -> parse_bulk_string(input, 6 + length * 10)
    <<"7":utf8, input:bits>> -> parse_bulk_string(input, 7 + length * 10)
    <<"8":utf8, input:bits>> -> parse_bulk_string(input, 8 + length * 10)
    <<"9":utf8, input:bits>> -> parse_bulk_string(input, 9 + length * 10)

    <<"\r\n":utf8, input:bits>> -> {
      let total_length = bit_array.byte_size(input)
      let content = bit_array.slice(input, 0, length)
      let rest = bit_array.slice(input, length, total_length - length)

      case content, rest {
        _, Ok(<<>>) -> Error(NotEnoughInput)
        _, Ok(<<"\r":utf8>>) -> Error(NotEnoughInput)

        Ok(content), Ok(<<"\r\n":utf8, rest:bits>>) ->
          case bit_array.to_string(content) {
            Ok(content) -> Ok(Parsed(String(content), rest))
            Error(_) -> Error(InvalidUnicode)
          }

        _, Ok(rest) -> Error(UnexpectedInput(rest))
        _, _ -> Error(UnexpectedInput(input))
      }
    }

    input -> Error(UnexpectedInput(input))
  }
}
