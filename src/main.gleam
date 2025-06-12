// Main entry point for the Redis server implementation
import carpenter/table
import gleam/erlang/process
import gleam/io
import gleam/option.{None}
import gleam/otp/actor
import gleam/string
import glisten
import redis/command.{type State}
import redis/resp

pub fn main() {
  // Set up and configure an ETS table for in-memory storage
  let assert Ok(ets) =
    table.build("mem-storage")
    |> table.privacy(table.Public)
    |> table.write_concurrency(table.WriteConcurrency)
    |> table.read_concurrency(True)
    |> table.decentralized_counters(True)
    |> table.compression(False)
    |> table.set

  // Start the TCP server on port 6379 with the handler and loop
  let assert Ok(_) =
    glisten.handler(fn(_conn) { #(ets, None) }, loop)
    |> glisten.serve(6379)

  // Prevent the process from exiting
  process.sleep_forever()
}

/// Message handler loop for each connection
fn loop(
  message: glisten.Message(a),
  state: State,
  conn: glisten.Connection(a),
) -> actor.Next(glisten.Message(a), State) {
  io.println("Received message")
  case message {
    // User messages are ignored
    glisten.User(_) -> actor.continue(state)
    // Packet messages are handled as Redis protocol
    glisten.Packet(data) -> handle_message(conn, state, data)
  }
}

/// Handles incoming packets, parses RESP, and dispatches commands
fn handle_message(
  conn: glisten.Connection(a),
  state: State,
  message: BitArray,
) -> actor.Next(glisten.Message(a), State) {
  case resp.parse(message) {
    // Ignore parse errors and continue
    Error(_) -> actor.continue(state)
    // On success, extract command and arguments and dispatch
    Ok(parsed) -> {
      let assert resp.Array([resp.String(command), ..arguments]) = parsed.data
      command.handle_command(conn, state, string.uppercase(command), arguments)
    }
  }
}
