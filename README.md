# json_parser

A JSON parser written in bash. No dependencies, one file, works on macOS and Linux.

It reads JSON and prints the values with their paths, so you can look inside a
file without installing `jq`.

```
$ json_parser.sh '{"user":{"name":"olek"},"tags":["bash"]}'
user.name="olek"
tags[0]="bash"
```

## Install

One command, installs the script into `~/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/zhirkoalexander-maker/olek115/main/install.sh | bash
```

If `~/.local/bin` is not in your PATH yet, add it:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Or download the script and run it from anywhere:

```bash
curl -fsSL https://raw.githubusercontent.com/zhirkoalexander-maker/olek115/main/json_parser.sh -o json_parser.sh
chmod +x json_parser.sh
./json_parser.sh '{"a":1}'
```

To remove it again:

```bash
curl -fsSL https://raw.githubusercontent.com/zhirkoalexander-maker/olek115/main/install.sh | bash -s uninstall
```

## Requirements

Bash 3.2 or newer. macOS ships with 3.2, Linux usually has something newer.
Nothing else is needed, no build step, no packages.

## Usage

```
json_parser.sh [options] [json|file]
```

The JSON can come from three places:

```bash
json_parser.sh '{"a":1}'              # as an argument
json_parser.sh data.json               # from a file
cat data.json | json_parser.sh         # from stdin
```

## What it can parse

Full JSON, as defined by the spec:

- objects, arrays, strings, numbers, `true`, `false`, `null`
- nested structures to any depth (up to `--max-depth`, 128 by default)
- escape sequences `\" \\ \/ \b \f \n \r \t`
- unicode escapes `\uXXXX`, including surrogate pairs for emoji
- empty objects `{}` and empty arrays `[]`
- whitespace anywhere between tokens

Numbers are checked against the spec, so `01`, `1.2.3`, `+5` and `.5` are
rejected. Duplicate keys are rejected too.

## Modes

Default output is `path=value`, one value per line:

```bash
$ json_parser.sh '{"a":1,"b":"x"}'
a=1
b="x"
```

| Flag | What it does |
|---|---|
| `--paths` | print only the paths |
| `--types` | print path, type and value |
| `--json` | rebuild the json from the parsed tree |
| `--pretty` | rebuild the json with indentation |
| `--count` | print how many values were found |
| `--sort` | sort the output lines |
| `--filter TEXT` | keep only paths containing TEXT |
| `--validate` | check the json, print nothing |

Examples:

```bash
$ json_parser.sh --paths '{"user":{"name":"olek"}}'
user.name

$ json_parser.sh --types '{"a":1,"b":"x"}'
a:number=1
b:string="x"

$ json_parser.sh --pretty '{"a":{"b":1}}'
{
  "a": {
    "b": 1
  }
}

$ json_parser.sh --count '{"a":1,"b":[1,2]}'
3

$ json_parser.sh --filter user '{"user":1,"other":2}'
user=1
```

## Paths

Paths show where a value lives:

- object key: `key`
- nested object: `parent.key`
- array item: `parent[0]`, index starts at zero
- keys that are not plain names are quoted: `"a b"`, `""`, `"c\"d"`

## Relaxed mode

JSON in the wild is not always strict. Three flags let you accept it:

| Flag | What it allows |
|---|---|
| `--allow-duplicate-keys` | the same key twice in one object |
| `--allow-trailing-comma` | a comma before `}` or `]` |
| `--allow-comments` | `// to the end of the line` and `/* ... */` |

```bash
$ json_parser.sh --allow-comments '{/* config */ "a":1 // first
}'
a=1
```

## Limits and errors

- the whole input is read into memory, there is no streaming mode
- nesting is limited by `--max-depth`, 128 by default
- input size is limited by `--max-size`, 1 MB by default
- `\u0000` is not supported, bash cannot hold a null byte

Errors go to stderr and the exit code is 1 for a broken input, 2 for a wrong
argument:

```
$ json_parser.sh '{"a":}'
error: unexpected character \} at pos 5
```

## Tests

```bash
bash tests.sh
```

## More

`SPEC.md` describes every mode, every error message and every limit in
detail.
