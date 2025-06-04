import gleeunit/should
import redis/resp.{Parsed}

pub fn parse_simple_string_pong_test() {
  <<"+PONG\r\n":utf8>>
  |> resp.parse
  |> should.be_ok
  |> should.equal(Parsed(resp.String("PONG"), <<>>))
}

pub fn parse_simple_string_pong_with_extra_test() {
  <<"+PONG\r\n+PONG\r\n":utf8>>
  |> resp.parse
  |> should.be_ok
  |> should.equal(Parsed(resp.String("PONG"), <<"+PONG\r\n":utf8>>))
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
