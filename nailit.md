
# NailIt

This is NailIt — a simple tool for creating literate programs (in the Knuthian sense).

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


## Blocks

A block can either be a **code block** or a **prose block**.

Prose blocks contain markup content, whereas code blocks contain… well, code, to be extracted out or to be explained by the surrounding prose blocks.

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

## Overall program structure

``` /src/nailit.nim
@{imports}
@{types}
@{constants}
@{functions}

when is_main_module:
  @{main program}
```


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

``` imports
import regex
import std/[strutils, tables, strtabs, paths, os]
import packages/docutils/[rst, rstgen, dochelpers]
import docopt
```

``` types
type
  @{block type definition}
```

``` constants
const
  @{compile-time regex}
```

``` functions
@{get blocks from source function}

@{weave function}

@{tangle function}

@{insert weaved into html template}

@{blocks function}
```

## Main program

``` read blocks from source file
let blocks =
  open($args["<source.md>"]).getBlocks()
```

The `weave` command supports supplying a template file via the option `--template`.

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

``` call tangle command
blocks.tangle(($args["<destdir/>"]).Path())
quit(0)
```

``` call blocks command
blocks.displayBlocks()
```

## Parsing blocks from the document

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
    @{parse each line and make new blocks}

  return totalBlocks
```

The two types of blocks in the markdown document live separately and cannot be nested, i.e. no code blocks in prose blocks, vice versa. The document is parsed using a switch that asks "is the current block a code block?", which is toggled by hitting a line starting with a `\`\`\``.

When a `\`\`\`` is encountered at the start of the document, it means this first block is a code block. Which means, this part of the code will insert an empty prose block before it, which shouldn't really matter for export purposes.

``` parse each line and make new blocks
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

Since the code block to be added is not actually inserted until it hits an ending `\`\`\``, name-setting is deferred until then.

``` set the name for the next block conditionally
nextNameBuffer = (
  if (m.group(1).a > -1) and (m.group(1).b > -1):
    line[m.group(1)]
  else:
    ""
)
```

A local helper function is defined here to handle things like spaces before and after the content, as well as potentially other headaches.

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

## Compile-time regex

* `codeBlockPtn` scans for code block *definitions*, like `\`\`\`` or `\`\`\` named block`.
* `codeBlockRefPtn` scans for code block *references*, like `@{named block}`
* `codeBlockRefSpacesPtn` is like `codeBlockRefPtn`, except it grabs whatever leading spaces are in it as well.

``` compile-time regex
codeBlockPtn = re2"^```(\s*(.+))?"
codeBlockRefPtn = re2"(@\{(.+)\})"
codeBlockRefSpacesPtn = re2"(?m)^(\s*?)@\{(.+?)\}"
```

## Weave

The `weave` command compiles an HTML page from a literate program.

``` weave function
proc weave(blocks: seq[Block]): string =
  var reflist: Table[string, CountTable[string]]
  var generatedHtml = ""

  # count code blocks
  @{initialize code block references list}
  @{count code block references}

  # generate HTML file

  # the header should be a link to itself so it can be linked somewhere else
  proc nameAsLink(m: RegexMatch2, s: string): string =
    return
      "<a href=\"#" & s[m.group(1)].nimIdentBackticksNormalize() & "\">" & s[m.group(0)] &
      "</a>"

  # turn each block to stuff
  for txblock in blocks:
    case txblock.kind
    of Code:
      @{convert a code block into html}
    of Prose:
      @{convert a prose block into html}
  return generatedHtml

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

let normName = txblock.name.nimIdentBackticksNormalize()

# start writing converted code block
generatedHtml &=
  @{code block html start}

# if the block is used somewhere else, say so
if reflist[txblock.name].len > 0:
  @{generate backlinks list for html code block}

# end write block
generatedHtml &=
  @{code block html end}
```

``` make the code block html-friendly
txblock.content
  .replace("<", "&lt;")
  .replace(">", "&gt;")
  .replace(codeBlockRefPtn, nameAsLink)
```

``` code block html start
"<div class=\"code-block\" id=\"" & normName & "\">" &
"<header class=\"block-title\">" &
  "<a href=\"#" & normName & "\">" & txblock.name & "</a>" &
"</header>" &
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
  let normI = i.nimIdentBackticksNormalize()
  generatedHtml &=
    "<a href=\"#" & normI & "\">" & i &
    # " &times; " & $(reflist[txblock.name][i]) &
    "</a> "
generatedHtml &= "</footer>"
```

Meanwhile, prose blocks are just converted wholesale. There's a `.. raw:: html` line prepended to the content in order to make the first line a <p>, so as to make the flow consistent.

``` convert a prose block into html
# just convert it wholesale
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



## Tangle

``` tangle function
proc tangle(blocks: seq[Block], dest: Path) =
  var codeBlkMap: Table[string, string]

  @{helper function to replace references with content}

  @{fill code block mappings}
  @{modify code block mappings with actual values}

  for key in codeBlkMap.keys:
    if key[0] == '/':
      @{save code block to file}
```

``` save code block to file
let outFileName = dest / Path(key[1 ..^ 1])
outFileName.parentDir.string.createDir()
outFileName.string.open(fmWrite).write(codeBlkMap[key])
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
    if codeBlkMap.hasKey txblock.name:
      stderr.writeLine "WARNING: replacing code block " & txblock.name
    codeBlkMap[txblock.name] = txblock.content
  of Prose:
    discard
```

## View Blocks

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
