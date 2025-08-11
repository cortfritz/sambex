# Sambex

Sambex is a library for interacting with SMB (Server Message Block) shares in Elixir.

## Questions

Q: Is it any good?
A:No. It's not. Not yet.

Q: Should you install it?
A: No. It's not ready yet.

Q: I used this in production and everything went wrong.
A: Thanks for doing QA - please report any issues on GitHub.

## Installation

Sambex can be installed by adding `sambex` to your list of dependencies
in `mix.exs`:

```elixir
def deps do
  [
    {:sambex, "~> 0.1.0-alpha2"}
  ]
end
```

## Usage

```elixir
iex> Sambex.list_dir("smb://localhost:445/private", "example2", "badpass")
{:ok, ["thing", "thing2"]}

iex> Sambex.read_file("smb://localhost:445/private/thing", "example2", "badpass")
{:ok, "thing\n"}

iex> Sambex.write_file("smb://localhost:445/private/thing2", "some content", "example2", "badpass")
{:ok, 12}
```
