# NailIt

A quite minimal [literate programming](http://www.literateprogramming.com/) tool, capable of formatting code with documentation, linking to sections of code and backreferencing other sections of code.

The tool converts from a Markdown file into HTML, fit for reading online or printing, if you want.

The tool supports converting only one Markdown file at the moment, if you want to use multiple files you'll have to combine them somehow… `cat *.md > onesource.md`?

Also, the tool does not at the moment support appending or changing code blocks "dynamically", so you have to uh… *nail it* I guess. It may be better that way, anyway—at least, in a "documentation" instead of "tutorial" setting.

## Building

Requires [Nim](https://nim-lang.org/) ≥1.6.x. The standard distribution should include the `nimble` tool, use `nimble build` to make a binary.

## Usage

``` command line arguments
NailIt - a simple literate programming tool.

Usage:
  nailit weave [--template=<template.html>] <source.md> [<out.html>]
  nailit tangle <source.md> <destdir/>
  nailit blocks <source.md>
  nailit (-h | --help)
  nailit --version

weave = generate a human-readable HTML document
        from literate programs.

tangle = generate compileable source code from
          literate programs.

blocks = see what blocks NailIt sees.
```

## Document structure

Documents are made up of **code blocks** and **prose blocks**.

**Code blocks** are, well, the actual program source code. To make a code block, surround code with a single line of \`\`\` before and after, with the preceding \`\`\` line containing the title as so: **\`\`\` Title of code block.**

**Prose blocks** are paragraphs and other stuff *around* the code blocks that explain what it does and why it does. These tend to be richer than just commenting code, although you could do both.

Code block titles that start with a `/` will be interpreted as file output relative to the `destdir` specified when calling the program.

Code blocks without a title will—at present—cause the program to crash.

Everything else outside of code blocks are considered **prose blocks** and will be formatted as Markdown… [Nim-flavored Markdown](https://nim-lang.org/docs/markdown_rst.html), at least.

Inside a code block, you can refer to other code blocks like so: **@{Name of other code block}**. They **must** live in its own line, with optional indentation. Indenting these references will add indentation to the inserted code block when tangling it, so you must keep that in mind when using whitespace-sensitive languages.

## Limitations

* Code block references must live in its own line.
* No support for multiple source files.
* No support for appending to code blocks, only replacing them (will output a warning).
* No support for syntax highlighting.

## Source code

Self-hosting sounds cool, so this README also contains NailIt's entire source code! It also serves as a practical explanation on what makes a literate program.

To make the compileable source code, do:

```
nailit tangle README.md .
```

To generate the literate program document, do:

```
nailit weave README.md > index.html
```

This explanation of the program is still a work-in-progress.

### Main program

The really nice `docopt` library is used to transform the command line help string into actual arguments the program can parse. The commands, at least, stay in-sync *and* self-documenting.

``` main program
let args = """
@{command line arguments}
""".docopt(
  version = "NailIt 0.1.1"
  )
@{read blocks from source file}

if args["weave"].to_bool():
  @{call weave command}

if args["tangle"].to_bool():
  @{call tangle command}

if args["blocks"].to_bool():
  @{call blocks command}
```

The `getBlocks` function takes in a string, so we use the stdlib to read a markdown document as a string to then pass into the function. Note here that in Nim, `a.getBlocks() == getBlocks(a)`.

``` read blocks from source file
let blocks =
  open($args["<source.md>"]).getBlocks()
```

The functions to call the features of NailIt will be described in the appropriate sections.

### Blocks

Blocks are just text with attributes that a

``` block type definition
BlockType = enum
  Prose
  Code

Block = object
  content: string
  case kind: BlockType
  of Code:
    name: string
  else:
    discard
```

#### Parsing blocks from the document

Basically, parsing is done on a line-by-line basis.

``` get blocks from source function
proc getBlocks(f: File): seq[Block] =
  @{helper function to add a block}

  var
    totalBlocks: seq[Block] = @[]
    isCodeBlock = false

  var
    contentBuffer = ""
    nextNameBuffer = ""

  for line in lines(f):
    @{parse a line and make new blocks}

  return totalBlocks
```

While parsing, the program looks for these specific patterns:

* `codeBlockPtn` scans for code block *definitions*, like `\`\`\`` or `\`\`\` named block`.
* `codeBlockRefPtn` scans for code block *references*, like `@{named block}`
* `codeBlockRefSpacesPtn` is like `codeBlockRefPtn`, except it grabs whatever leading spaces are in it as well.

``` regex patterns
codeBlockPtn = re2"^```(\s*(.+))?"
codeBlockRefPtn = re2"(@\{(.+)\})"
codeBlockRefSpacesPtn = re2"(?m)^(\s*?)@\{(.+?)\}"
```

The two types of blocks in the markdown document live separately and cannot be nested, i.e. no code blocks in prose blocks, vice versa. The document is parsed using a switch that asks "is the current block a code block?", which is toggled by hitting a line starting with a `\`\`\``.

When a `\`\`\`` is encountered at the start of the document, it means this first block is a code block. Which means, this part of the code will insert an empty prose block before it, which shouldn't really matter for export purposes.

Since the code block to be added is not actually inserted until it hits an ending `\`\`\``, name-setting is deferred until then, just like content-setting.

``` parse a line and make new blocks
if (var m: RegexMatch2; line.match(codeBlockPtn, m)):
  totalBlocks.addBlock(
    (if isCodeBlock: Code else: Prose),
    contentBuffer,
    nextNameBuffer
  )
  # TODO: BUG a blank line in place of this line makes the
  # below line have incorrect indentation
  @{set the name for the next block conditionally}
  contentBuffer = ""
  isCodeBlock = not isCodeBlock
else:
  contentBuffer &= line & "\n"
```

Names for code blocks are optional. The regex library will have its ranges set below 0 if it can't find a name, so I'm taking it into account here.

``` set the name for the next block conditionally
nextNameBuffer = (
  if (m.group(1).a > -1) and (m.group(1).b > -1):
    line[m.group(1)]
  else:
    ""
  )
```

Block-adding is done by a helper function `addBlock`. This is to handle things like spaces before and after the content, as well as potentially other headaches.

``` helper function to add a block
proc addBlock(
    blocks: var seq[Block],
    parseAs: BlockType,
    contentBuf: string,
    nameBuf: string = ""
): void =
  case parseAs
  of Prose:
    blocks.add Block(
      kind: Prose,
      content: contentBuf
    )
  of Code:
    blocks.add Block(
      kind: Code,
      name: nameBuf,
      content: (
        @{trim spaces on either end of the content}
      )
    )
```

Content may have unnecessary newlines at the start and/or the end that we don't really need, so we may as well strip them out.

``` trim spaces on either end of the content
var contentStripped = contentBuf

if contentStripped.len == 1:
  contentStripped = ""
else:
  if contentStripped[0] == '\n':
    contentStripped = contentStripped[1 ..^ 1]
  if contentStripped[^1] == '\n':
    contentStripped = contentStripped[0 ..^ 2]

contentStripped
```

### Weave

The `weave` command compiles an HTML page from a literate program.

``` weave function
proc weave(blocks: seq[Block]): string =
  var reflist: Table[string, CountTable[string]]
  var generatedHtml = ""

  @{initialize code block references list}
  @{count code block references}
  @{helper function to transform names to links}

  # turn each block to stuff
  for txblock in blocks:
    case txblock.kind
    of Code:
      @{convert a code block into html}
    of Prose:
      @{convert a prose block into html}
  return generatedHtml

```

The header should be a link to itself so it can be linked somewhere else

``` function to normalize labels
proc normalize(s: string): string =
  return s
    .replace("_","")
    .replace(" ","")
    .tolowerascii()
```

``` helper function to transform names to links
proc nameAsLink(m: RegexMatch2, s: string): string =
  return
    "<a href=\"#" &
      s[m.group(1)].normalize() &
    "\">" &
      s[m.group(0)] &
    "</a>"
```

A code block is usually referenced by other code blocks, so for every named code block we need to track how many times they're referenced or invoked in other code blocks.

``` initialize code block references list
for txblock in blocks:
  case txblock.kind
  of Code:
    if not reflist.hasKey txblock.name:
      reflist[txblock.name] = initCountTable[string](0)
  of Prose:
    discard
```

``` count code block references
for txblock in blocks:
  case txblock.kind
  of Code:
    for m in txblock.content.findAll(codeBlockRefPtn):
      let keyName = txblock.content[m.captures[1]]

      # skip empty names
      if keyName.len < 1: continue

      if reflist.hasKey keyName:
        reflist[keyName].inc txblock.name
      else:
        stderr.writeLine "WARNING: key " & keyName & " not found!"
  of Prose:
    discard
```

``` convert a code block into html
# TODO: make it convert properly...
let escapedCode =
  @{make the code block html-friendly}

let normName = txblock.name.normalize()

# start writing converted code block
generatedHtml &= (
  @{code block html start}
)

# if the block is used somewhere else, say so
if txblock.name.len > 0 and reflist[txblock.name].len > 0:
  @{generate backlinks list for html code block}

# end write block
generatedHtml &= (
  @{code block html end}
)
```

``` make the code block html-friendly
txblock.content
  .replace("&", "&amp;")
  .replace("<", "&lt;")
  .replace(">", "&gt;")
  .replace(codeBlockRefPtn, nameAsLink)
```

``` code block html start
if txblock.name.len > 0:
  @{starting html for named code block}
else:
  @{starting html for anonymous code block}
```

``` starting html for named code block
"<div class=\"code-block\" id=\"" & normName & "\">" &
  "<header class=\"block-title\">" &
    "<a href=\"#" & normName & "\">" & txblock.name & "</a>" &
  "</header>" &
  "<pre><code>" &
    escapedCode &
  "</code></pre>"
```

``` starting html for anonymous code block
"<div class=\"code-block\">" &
  "<pre><code>" &
    escapedCode &
  "</code></pre>"
```

``` code block html end
"</div>"
```

``` generate backlinks list for html code block
generatedHtml &= "<footer class=\"used-by\">Used by "

for i in reflist[txblock.name].keys:
  let normI = i.normalize()
  generatedHtml &=
    "<a href=\"#" & normI & "\">" & i &
    # " &times; " & $(reflist[txblock.name][i]) &
    "</a> "
generatedHtml &= "</footer>"
```

Meanwhile, prose blocks are just converted wholesale. There's a `.. raw:: html` line prepended to the content in order to make the first line a <p>, so as to make the flow consistent.

``` convert a prose block into html
let toParaHack = ".. raw:: html\n\n" & txblock.content
generatedHtml &=
  toParaHack.rstToHtml(
    {
      roSupportMarkdown, roPreferMarkdown, roSandboxDisabled,
      roSupportRawDirective,
    },
    modeStyleInsensitive.newStringTable(),
  )
```

``` insert weaved into html template
proc intoHtmlTemplate(weaved: string, temp: string = "", title: string = ""): string =
  if temp.strip() == "":
    return """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>""" & title & """</title>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <link rel="stylesheet" href="css/screen.css" media="screen,projection,tv">
      <link rel="stylesheet" href="css/print.css" media="print">
    </head>
    <body>
    """ & weaved & """
    </body>
    </html>
    """
  else:
    # <!-- TITLE --> is replaced with the document title.
    # <!-- BODY --> is replaced with the body of the document.
    # The spellings need to exact.
    return temp.replace("<!-- TITLE -->", title).replace("<!-- BODY -->", weaved)
```

#### Calling the weave command

The `weave` command supports supplying a template file via the option `--template`. This is optional, as the command has a "default" template that it uses.

``` call weave command
let weaved = blocks.weave().intoHtmlTemplate(
  temp = (
    if args["--template"].kind == vkNone:
      ""
    else:
      open($args["--template"]).readAll()
  ),
  title = $args["<source.md>"], # TODO
)

if args["<out.html>"].kind == vkNone:
  echo weaved
else:
  open($args["<out.html>"], fmWrite).write(weaved)
quit(0)
```


### Tangle

``` tangle function
proc tangle(blocks: seq[Block], dest: string) =
  var codeBlkMap: Table[string, string]

  @{helper function to replace references with content}

  @{fill code block mappings}
  @{modify code block mappings with actual values}

  for key in codeBlkMap.keys:
    if key.len > 0 and key[0] == '/':
      @{save code block to file}
```

``` save code block to file
let outFileName = [dest, key[1 ..^ 1]].join($os.DirSep)
outFileName.parentDir.createDir()
outFileName.open(fmWrite).write(codeBlkMap[key])
stderr.writeLine "INFO: wrote to file " & outFileName.string
```

``` helper function to replace references with content
proc replaceReferencesWithContent(m: RegexMatch2, s: string): string =
  let keyName = s[m.group(1)]

  if codeBlkMap.hasKey keyName:
    # indent each line with the same amount of spaces as
    # the indentation of the references
    let initialNLAndSpaces = s[m.group(0)]
    if (
      let initialSpaces = initialNLAndSpaces.replace("\n", "")
      initialSpaces.len > 0
    ):
      var
        paddedCodeLines = initialSpaces
        isInitialLine = true
      for line in codeBlkMap[keyName].strip().splitLines():
        if isInitialLine:
          paddedCodeLines &= line & "\n"
          isInitialLine = false
        else:
          paddedCodeLines &= initialSpaces & line & '\n'
      return paddedCodeLines
    return initialNLAndSpaces & codeBlkMap[keyName]

  stderr.writeLine "WARNING: key " & keyName & " not found!"
  return ""
```

``` modify code block mappings with actual values
for codeBlk in codeBlkMap.mvalues: # :(
  for _ in 0 .. codeBlk.findAll(codeBlockRefSpacesPtn).len: # :(
    codeBlk = codeBlk.replace(codeBlockRefSpacesPtn, replaceReferencesWithContent)
```

``` fill code block mappings
for txblock in blocks:
  case txblock.kind
  of Code:
    if txblock.name.len < 1: continue
    if codeBlkMap.hasKey txblock.name:
      stderr.writeLine "WARNING: replacing code block " & txblock.name
    codeBlkMap[txblock.name] = txblock.content
  of Prose:
    discard
```

``` call tangle command
blocks.tangle(($args["<destdir/>"]))
quit(0)
```

### View Blocks

``` blocks function
proc displayBlocks(blocks: seq[Block]) =
  var num = 1
  for b in blocks:
    let blockTitle =
      "Block " & (
        case b.kind
        of Prose: "P."
        of Code: "C."
      ) & $num & (
        case b.kind
        of Prose: ""
        of Code: " \"" & b.name & "\""
      )
    echo '-'.repeat(blockTitle.len)
    echo blockTitle
    echo '-'.repeat(blockTitle.len)
    num += 1
    echo b.content
    echo '-'.repeat(blockTitle.len) & '\n'
```


``` call blocks command
blocks.displayBlocks()
```

### Overall program structure

``` /src/nailit.nim
@{imports}
@{types}
@{constants}
@{functions}

when is_main_module:
  @{main program}
```

``` imports
import regex
import std/[strutils, tables, strtabs, os]
import packages/docutils/[rst, rstgen]
import docopt
```

``` types
type
  @{block type definition}
```

``` constants
const
  @{regex patterns}
```

``` functions
@{function to normalize labels}

@{get blocks from source function}

@{weave function}

@{tangle function}

@{insert weaved into html template}

@{blocks function}
```
