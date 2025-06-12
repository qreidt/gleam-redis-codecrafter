import gleam/erlang/process
import gleam/io
import gleam/option.{None}
import gleam/otp/actor
import gleam/string
import glisten
import redis/command
import redis/resp

pub fn main() {
  // Ensures gleam doesn't complain about unused imports in stage 1 (feel free to remove this!)
  let _ = glisten.handler
  let _ = glisten.serve
  let _ = process.sleep_forever
  let _ = actor.continue
  let _ = None

  // You can use print statements as follows for debugging, they'll be visible when running tests.
  io.println("Logs from your program will appear here!")

  let assert Ok(_) =
    glisten.handler(fn(_conn) { #(Nil, None) }, loop)
    |> glisten.serve(6379)

  process.sleep_forever()
}

/// This function is called when a message is received.
fn loop(
  message: glisten.Message(a),
  state: state,
  conn: glisten.Connection(a),
) -> actor.Next(glisten.Message(a), state) {
  io.println("Received message")
  case message {
    glisten.User(_) -> actor.continue(state)
    glisten.Packet(data) -> handle_message(conn, state, data)
  }
}

fn handle_message(
  conn: glisten.Connection(a),
  state: state,
  message: BitArray,
) -> actor.Next(glisten.Message(a), state) {
  case resp.parse(message) {
    Error(_) -> actor.continue(state)
    Ok(parsed) -> {
      let assert resp.Array([resp.String(command), ..arguments]) = parsed.data
      command.handle_command(conn, state, string.uppercase(command), arguments)
    }
  }
}
