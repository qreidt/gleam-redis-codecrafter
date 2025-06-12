import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub type RespData {
  String(content: String)
  Array(elements: List(RespData))
  Null
}

pub type ParseError {
  UnexpectedInput(got: BitArray)
  InvalidUnicode
  NotEnoughInput
}

pub type Parsed {
  Parsed(data: RespData, remaining_input: BitArray)
}

pub fn encode(input: RespData) -> BitArray {
  en(<<>>, input)
}

fn en(buffer: BitArray, input: RespData) -> BitArray {
  case input {
    String(input) -> <<buffer:bits, en_string(input):bits>>
    Array(elements) -> <<buffer:bits, en_array(elements):bits>>
    Null -> <<buffer:bits, "_\r\n":utf8>>
  }
}

pub fn encode_simple_string(input: String) -> BitArray {
  <<string.concat(["+", input, "\r\n"]):utf8>>
}

fn en_string(input: String) -> BitArray {
  let bytes = int.to_string(bit_array.byte_size(<<input:utf8>>))
  let content = "$" <> bytes <> "\r\n" <> input <> "\r\n"

  <<content:utf8>>
}

fn en_array(elements: List(RespData)) -> BitArray {
  let length = int.to_string(list.length(elements))
  let buf = <<string.concat(["*", length, "\r\n"]):utf8>>
  list.fold(elements, buf, en)
}

pub fn parse(input: BitArray) -> Result(Parsed, ParseError) {
  case input {
    <<"_\r\n":utf8, rest:bits>> -> parse_null(rest)
    <<"$-1\r\n":utf8, rest:bits>> -> parse_null(rest)
    <<"*-1\r\n":utf8, rest:bits>> -> parse_null(rest)

    <<"+":utf8, rest:bits>> -> parse_simple_string(rest, <<>>)
    <<"$":utf8, rest:bits>> -> parse_bulk_string(rest)
    <<"*":utf8, rest:bits>> -> parse_array(rest)

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
/// A bulk string represents a single binary string. The string can be of any size, but by default, Redis limits it
/// to 512 MB (see the proto-max-bulk-len configuration directive).
/// 
/// RESP encodes bulk strings in the following way:
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
fn parse_bulk_string(input: BitArray) -> Result(Parsed, ParseError) {
  use #(length, input) <- result.try(parse_raw_int(input, 0))

  let total_length = bit_array.byte_size(input)
  let content = bit_array.slice(input, 0, length)
  let rest = bit_array.slice(input, length, total_length - length)

  case content, rest {
    _, Ok(<<>>) -> Error(NotEnoughInput)
    _, Ok(<<"\r":utf8>>) -> Error(NotEnoughInput)

    Ok(content), Ok(<<"\r\n":utf8, rest:bits>>) -> {
      use content <- result.try(parse_unicode(content))
      Ok(Parsed(String(content), rest))
    }

    _, Ok(rest) -> Error(UnexpectedInput(rest))
    _, _ -> Error(UnexpectedInput(input))
  }
}

///
/// ## Arrays
/// Clients send commands to the Redis server as RESP arrays. Similarly, some Redis commands that return collections of
/// elements use arrays as their replies. An example is the LRANGE command that returns elements of a list.
/// 
/// RESP Arrays' encoding uses the following format:
/// ```
/// *<number-of-elements>\r\n<element-1>...<element-n>
/// ```
/// - An asterisk (*) as the first byte.
/// - One or more decimal digits (0..9) as the number of elements in the array as an unsigned, base-10 value.
/// - The CRLF terminator.
/// - An additional RESP type for every element of the array.
/// 
/// So an empty Array is just the following:
/// ```
/// *0\r\n
/// ```
/// 
/// Whereas the encoding of an array consisting of the two bulk strings "hello" and "world" is:
/// ```
/// *2\r\n$5\r\nhello\r\n$5\r\nworld\r\n
/// ```
/// 
/// As you can see, after the *<count>CRLF part prefixing the array, the other data types that compose the array are
/// concatenated one after the other. For example, an Array of three integers is encoded as follows:
/// ```
/// *3\r\n:1\r\n:2\r\n:3\r\n
/// ```
/// Arrays can contain mixed data types. For instance, the following encoding is of a list of four integers and a bulk string:
/// ```
/// *5\r\n
/// :1\r\n
/// :2\r\n
/// :3\r\n
/// :4\r\n
/// $5\r\n
/// hello\r\n
/// ```
/// 
/// The first line the server sent is *5\r\n. This numeric value tells the client that five reply types are about to
/// follow it. Then, every successive reply constitutes an element in the array.
/// 
/// All of the aggregate RESP types support nesting. For example, a nested array of two arrays is encoded as follows:
/// ```
/// *2\r\n
/// *3\r\n
/// :1\r\n
/// :2\r\n
/// :3\r\n
/// *2\r\n
/// +Hello\r\n
/// -World\r\n
/// ```
/// The above encodes a two-element array. The first element is an array that, in turn, contains three integers (1, 2, 3).
/// The second element is another array containing a simple string and an error.
/// 
fn parse_array(input: BitArray) -> Result(Parsed, ParseError) {
  case parse_raw_int(input, 0) {
    Ok(#(count, input)) ->
      case parse_elements(input, count, []) {
        Ok(#(elements, input)) -> Ok(Parsed(Array(elements), input))
        Error(e) -> Error(e)
      }
    Error(e) -> Error(e)
  }
}

///
/// ## Nulls
/// The null data type represents non-existent values.
/// 
/// Nulls' encoding is the underscore (_) character, followed by the CRLF terminator (\r\n). Here's Null's raw RESP encoding:
/// 
/// ```
/// _\r\n
/// ```
/// 
fn parse_null(rest: BitArray) -> Result(Parsed, ParseError) {
  Ok(Parsed(data: Null, remaining_input: rest))
}

/// 
/// Helpers 
/// 
fn parse_elements(
  input: BitArray,
  remaining: Int,
  elements: List(RespData),
) -> Result(#(List(RespData), BitArray), ParseError) {
  case remaining > 0 {
    False -> Ok(#(list.reverse(elements), input))
    True -> {
      case parse(input) {
        Ok(parsed) -> {
          let elements = [parsed.data, ..elements]
          parse_elements(parsed.remaining_input, remaining - 1, elements)
        }

        Error(e) -> Error(e)
      }
    }
  }
}

fn parse_unicode(input: BitArray) {
  case bit_array.to_string(input) {
    Ok(input) -> Ok(input)
    Error(_) -> Error(InvalidUnicode)
  }
}

fn parse_raw_int(
  input: BitArray,
  int: Int,
) -> Result(#(Int, BitArray), ParseError) {
  case input {
    <<"0":utf8, input:bits>> -> parse_raw_int(input, int * 10)
    <<"1":utf8, input:bits>> -> parse_raw_int(input, 1 + int * 10)
    <<"2":utf8, input:bits>> -> parse_raw_int(input, 2 + int * 10)
    <<"3":utf8, input:bits>> -> parse_raw_int(input, 3 + int * 10)
    <<"4":utf8, input:bits>> -> parse_raw_int(input, 4 + int * 10)
    <<"5":utf8, input:bits>> -> parse_raw_int(input, 5 + int * 10)
    <<"6":utf8, input:bits>> -> parse_raw_int(input, 6 + int * 10)
    <<"7":utf8, input:bits>> -> parse_raw_int(input, 7 + int * 10)
    <<"8":utf8, input:bits>> -> parse_raw_int(input, 8 + int * 10)
    <<"9":utf8, input:bits>> -> parse_raw_int(input, 9 + int * 10)
    <<"\r\n":utf8, input:bits>> -> Ok(#(int, input))
    <<"\r":utf8>> | <<>> -> Error(NotEnoughInput)
    _ -> Error(UnexpectedInput(input))
  }
}
