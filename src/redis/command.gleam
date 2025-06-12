import carpenter/table.{type Set}
import gleam/bytes_builder
import gleam/io
import gleam/otp/actor
import glisten
import redis/resp

pub type State =
  Set(String, resp.RespData)

pub fn handle_command(
  conn: glisten.Connection(a),
  state: State,
  command: String,
  arguments: List(resp.RespData),
) -> actor.Next(glisten.Message(a), Set(String, resp.RespData)) {
  io.println("Command: " <> command)
  case command {
    "PING" -> handle_ping(conn, state)
    "ECHO" -> handle_echo(conn, state, arguments)
    "SET" -> handle_set(conn, state, arguments)
    "GET" -> handle_get(conn, state, arguments)

    _ -> panic as { "Unknown Command: " <> command }
  }
}

fn handle_ping(
  conn: glisten.Connection(a),
  state: State,
) -> actor.Next(glisten.Message(a), State) {
  let pong = resp.encode(resp.String("PONG"))
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(pong))

  actor.continue(state)
}

fn handle_echo(
  conn: glisten.Connection(a),
  state: State,
  arguments: List(resp.RespData),
) -> actor.Next(glisten.Message(a), State) {
  let assert [value] = arguments

  let data = resp.encode(value)
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(data))

  actor.continue(state)
}

fn handle_set(
  conn: glisten.Connection(a),
  state: State,
  arguments: List(resp.RespData),
) -> actor.Next(glisten.Message(a), State) {
  let assert [resp.String(key), value, ..] = arguments

  table.insert(state, [#(key, value)])

  let data = resp.encode_simple_string("OK")
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(data))

  actor.continue(state)
}

fn handle_get(
  conn: glisten.Connection(a),
  state: State,
  arguments: List(resp.RespData),
) -> actor.Next(glisten.Message(a), State) {
  let assert [resp.String(key), ..] = arguments

  let stored_value = case table.lookup(state, key) {
    [#(_, value)] -> value
    _ -> resp.Null
  }

  let data = resp.encode(stored_value)
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(data))

  actor.continue(state)
}
