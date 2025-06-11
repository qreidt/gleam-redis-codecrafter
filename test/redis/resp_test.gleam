import gleam/string
import gleeunit/should
import redis/resp.{Parsed}

pub fn parse_simple_string_pong_test() {
  <<"+PONG\r\n":utf8>>
  |> resp.parse
  |> should.be_ok
  |> should.equal(Parsed(data: resp.String("PONG"), remaining_input: <<>>))
}

pub fn parse_simple_string_pong_with_extra_test() {
  <<"+PONG\r\n+PONG\r\n":utf8>>
  |> resp.parse
  |> should.be_ok
  |> should.equal(
    Parsed(data: resp.String("PONG"), remaining_input: <<"+PONG\r\n":utf8>>),
  )
}

pub fn parse_simple_string_invalid_unicode_test() {
  <<"+POG":utf8, 123_456:size(128), "\r\n":utf8>>
  |> resp.parse
  |> should.be_error
  |> should.equal(resp.InvalidUnicode)
}

pub fn parse_simple_string_not_enough_input_test() {
  <<"+POG":utf8>>
  |> resp.parse
  |> should.be_error
  |> should.equal(resp.NotEnoughInput)
}

pub fn parse_bulk_string_pong_test() {
  <<"$4\r\nPONG\r\n":utf8>>
  |> resp.parse
  |> should.be_ok
  |> should.equal(Parsed(data: resp.String("PONG"), remaining_input: <<>>))
}

pub fn parse_bulk_string_10_test() {
  <<"$10\r\n0123456789\r\n":utf8>>
  |> resp.parse
  |> should.be_ok
  |> should.equal(
    Parsed(data: resp.String("0123456789"), remaining_input: <<>>),
  )
}

pub fn parse_bulk_string_203_test() {
  let string = string.repeat("0123456789", 20) <> "abc"

  <<"$203\r\n":utf8, string:utf8, "\r\n":utf8, "extra!!!":utf8>>
  |> resp.parse
  |> should.be_ok
  |> should.equal(
    Parsed(data: resp.String(string), remaining_input: <<"extra!!!":utf8>>),
  )
}

pub fn parse_bulk_string_not_enough_input_test() {
  <<"$10\r\n0123456789\r":utf8>>
  |> resp.parse
  |> should.be_error
  |> should.equal(resp.NotEnoughInput)
}

pub fn parse_bulk_string_unexpected_input_test() {
  <<"$10\r\n0123456789_":utf8>>
  |> resp.parse
  |> should.be_error
  |> should.equal(resp.UnexpectedInput(<<"_":utf8>>))
}

pub fn parse_bulk_string_invalid_input_test() {
  <<"$4\r\n":utf8, 255, 255, 255, 255, "\r\n":utf8>>
  |> resp.parse
  |> should.be_error
  |> should.equal(resp.InvalidUnicode)
}

pub fn parse_array_empty_test() {
  <<"*0\r\n":utf8>>
  |> resp.parse
  |> should.be_ok
  |> should.equal(Parsed(data: resp.Array([]), remaining_input: <<>>))
}

pub fn parse_array_hello_world_test() {
  <<"*2\r\n$5\r\nhello\r\n$5\r\nworld\r\n":utf8>>
  |> resp.parse
  |> should.be_ok
  |> should.equal(
    Parsed(
      data: resp.Array([resp.String("hello"), resp.String("world")]),
      remaining_input: <<>>,
    ),
  )
}
