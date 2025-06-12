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
  // Set up and configure an ETS table
  let assert Ok(ets) =
    table.build("mem-storage")
    |> table.privacy(table.Public)
    |> table.write_concurrency(table.WriteConcurrency)
    |> table.read_concurrency(True)
    |> table.decentralized_counters(True)
    |> table.compression(False)
    |> table.set

  // You can use print statements as follows for debugging, they'll be visible when running tests.
  io.println("Logs from your program will appear here!")

  let assert Ok(_) =
    glisten.handler(fn(_conn) { #(ets, None) }, loop)
    |> glisten.serve(6379)

  process.sleep_forever()
}

/// This function is called when a message is received.
fn loop(
  message: glisten.Message(a),
  state: State,
  conn: glisten.Connection(a),
) -> actor.Next(glisten.Message(a), State) {
  io.println("Received message")
  case message {
    glisten.User(_) -> actor.continue(state)
    glisten.Packet(data) -> handle_message(conn, state, data)
  }
}

fn handle_message(
  conn: glisten.Connection(a),
  state: State,
  message: BitArray,
) -> actor.Next(glisten.Message(a), State) {
  case resp.parse(message) {
    Error(_) -> actor.continue(state)
    Ok(parsed) -> {
      let assert resp.Array([resp.String(command), ..arguments]) = parsed.data
      command.handle_command(conn, state, string.uppercase(command), arguments)
    }
  }
}
