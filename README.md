# json_parser

A JSON parser written in bash. One file, no dependencies, works on macOS and
Linux.

It reads JSON and prints every value with the path where it was found, so you
can look inside a file without installing `jq`.

```
$ json_parser '{"user":{"name":"olek"},"tags":["bash"]}'
user.name="olek"
tags[0]="bash"
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zhirkoalexander-maker/olek115/main/install.sh | bash
```

The installer puts the script into `~/.local/bin`. Add it to your PATH if it
is not there yet:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then:

```bash
json_parser help
```

Or skip the installer and run the script from anywhere:

```bash
curl -fsSL https://raw.githubusercontent.com/zhirkoalexander-maker/olek115/main/json_parser.sh -o json_parser.sh
chmod +x json_parser.sh
./json_parser '{"a":1}'
```

To remove it:

```bash
curl -fsSL https://raw.githubusercontent.com/zhirkoalexander-maker/olek115/main/install.sh | bash -s uninstall
```

## Requirements

Bash 3.2 or newer. macOS ships with 3.2, Linux usually has something newer.
Nothing else is needed.

## Usage

```
json_parser [options] [json|file]
```

The JSON comes from one of three places:

```bash
json_parser '{"a":1}'          # as an argument
json_parser data.json          # from a file
cat data.json | json_parser    # from stdin
```

## Modes

The default output is `path=value`, one value per line:

```bash
$ json_parser '{"a":1,"b":"x"}'
a=1
b="x"
```

| Mode | What it prints |
|---|---|
| default | `path=value` for every value |
| `--paths` | only the paths |
| `--types` | the path with the type of the value |
| `--count` | how many values were found |
| `--sort` | the output, sorted |
| `--filter TEXT` | only the paths that contain TEXT |

```bash
$ json_parser --paths '{"user":{"name":"olek"}}'
user.name

$ json_parser --types '{"a":1,"b":"x","c":true,"d":null}'
a:number=1
b:string="x"
c:boolean=true
d:null=null

$ json_parser --count '{"a":1,"b":[1,2]}'
3

$ json_parser --sort '{"z":1,"a":2}'
a=2
z=1

$ json_parser --filter tag '{"tag":1,"other":2}'
tag=1
```

## Paths

- object key: `key`
- nested object: `parent.key`
- array item: `parent[0]`, the index starts at zero
- keys that are not plain names are quoted: `"a b"`, `""`, `"c\"d"`
- the root itself is printed as `(root)`

## Options

| Option | What it does |
|---|---|
| `-h`, `--help`, `help` | show the help |
| `-v`, `--version` | show the version |
| `-q`, `--quiet` | no output, only the exit status |
| `--validate` | check the json and exit |
| `--max-depth N` | nesting depth limit, 128 by default |
| `--max-size N` | input size limit in bytes, 1 MB by default |
| `--allow-duplicate-keys` | accept the same key twice in one object |
| `--allow-trailing-comma` | accept a comma before `}` or `]` |
| `--allow-comments` | accept `//` and `/* */` comments |

## What it parses

Full JSON: objects, arrays, strings, numbers, `true`, `false` and `null`.
Nested structures to any depth, all escape sequences, `\uXXXX` including
surrogate pairs, empty objects and empty arrays.

Numbers are checked against the spec, so `01`, `1.2.3`, `+5` and `.5` are
rejected. Duplicate keys are rejected too.

## Errors

Errors go to stderr, the exit code is 1 for a broken input and 2 for a wrong
argument:

```
$ json_parser '{"a":}'
error: unexpected character \} at pos 5
```

## Tests

```bash
bash tests.sh
```

`SPEC.md` has the full description of every mode and every error message.
