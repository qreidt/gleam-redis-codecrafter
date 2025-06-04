import gleam/io

import gleam/bytes_builder
import gleam/erlang/process
import gleam/option.{None}
import gleam/otp/actor
import glisten

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
    glisten.handler(fn(_conn) { #(Nil, None) }, handle_message)
    |> glisten.serve(6379)

  process.sleep_forever()
}

/// This function is called when a message is received.
fn handle_message(
  _message: glisten.Message(a),
  state: state,
  conn: glisten.Connection(a),
) -> actor.Next(glisten.Message(a), state) {
  io.println("Received message")
  let assert Ok(_) = glisten.send(conn, bytes_builder.from_string("+PONG\r\n"))
  actor.continue(state)
}
