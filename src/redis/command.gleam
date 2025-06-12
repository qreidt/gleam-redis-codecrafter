import gleam/bytes_builder
import gleam/io
import gleam/otp/actor
import glisten
import redis/resp

pub fn handle_command(
  conn: glisten.Connection(a),
  state: state,
  command: String,
  arguments: List(resp.RespData),
) -> actor.Next(glisten.Message(a), state) {
  io.println("Command: " <> command)
  case command {
    "PING" -> handle_ping(conn, state)
    "ECHO" -> handle_echo(conn, state, arguments)

    _ -> panic as { "Unknown Command: " <> command }
  }
}

fn handle_ping(
  conn: glisten.Connection(a),
  state: state,
) -> actor.Next(glisten.Message(a), state) {
  let pong = resp.encode(resp.String("PONG"))
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(pong))

  actor.continue(state)
}

fn handle_echo(
  conn: glisten.Connection(a),
  state: state,
  arguments: List(resp.RespData),
) -> actor.Next(glisten.Message(a), state) {
  let assert [value] = arguments

  let data = resp.encode(value)
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(data))

  actor.continue(state)
}
