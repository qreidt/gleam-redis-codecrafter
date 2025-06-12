// Implements Redis command handlers: PING, ECHO, SET, GET
// Uses an in-memory table for storage
import carpenter/table.{type Set}
import gleam/bytes_builder
import gleam/io
import gleam/otp/actor
import glisten
import redis/resp

// State type: a table mapping String keys to RespData values
pub type State =
  Set(String, resp.RespData)

// Main command dispatcher: routes commands to their handlers
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
    // Unknown command: crash for now
    _ -> panic as { "Unknown Command: " <> command }
  }
}

// Handles the PING command: replies with PONG
fn handle_ping(
  conn: glisten.Connection(a),
  state: State,
) -> actor.Next(glisten.Message(a), State) {
  let pong = resp.encode(resp.String("PONG"))
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(pong))
  actor.continue(state)
}

// Handles the ECHO command: replies with the same value
fn handle_echo(
  conn: glisten.Connection(a),
  state: State,
  arguments: List(resp.RespData),
) -> actor.Next(glisten.Message(a), State) {
  // ECHO expects a single argument
  let assert [value] = arguments
  let data = resp.encode(value)
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(data))
  actor.continue(state)
}

// Handles the SET command: stores a value in the table
fn handle_set(
  conn: glisten.Connection(a),
  state: State,
  arguments: List(resp.RespData),
) -> actor.Next(glisten.Message(a), State) {
  // SET expects at least a key and a value
  let assert [resp.String(key), value, ..] = arguments
  table.insert(state, [#(key, value)])
  let data = resp.encode_simple_string("OK")
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(data))
  actor.continue(state)
}

// Handles the GET command: retrieves a value from the table
fn handle_get(
  conn: glisten.Connection(a),
  state: State,
  arguments: List(resp.RespData),
) -> actor.Next(glisten.Message(a), State) {
  // GET expects at least a key
  let assert [resp.String(key), ..] = arguments
  let stored_value = case table.lookup(state, key) {
    [#(_, value)] -> value
    _ -> resp.Null
  }
  let data = resp.encode(stored_value)
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(data))
  actor.continue(state)
}
