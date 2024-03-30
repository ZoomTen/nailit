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

**Code blocks** are, well, the actual program source code. To make a code block, surround code with a single line of \`\`\` before and after the code portion. The `\`\`\`` line before the code can take one of four forms:

1. `\`\`\``: an unnamed block interpreted as plain text;
2. `\`\`\`lang`: an unnamed block interpreted as code in `lang`;
3. `\`\`\`lang name of block`: a block named `name of block` interpreted as code in `lang`;
4. `\`\`\` name of block`: a block named `name of block` interpreted as plain text. **In this form, at least one space is needed before the block's name**.

Code block titles that start with a `/` will be interpreted as file output relative to the `destdir` specified when calling the program.

Inside a code block, you can refer to other code blocks like so: `@{Name of other code block}`. They **must** live in its own line, with optional indentation. Indenting these references will add indentation to the inserted code block when tangling it, so you must keep that in mind when using whitespace-sensitive languages.

**Prose blocks** are paragraphs and other stuff *around* the code blocks that explain what it does and why it does. They are formatted as as Markdown… [Nim-flavored Markdown](https://nim-lang.org/docs/markdown_rst.html), at least.

## Limitations

* Code block references must live in its own line.
* No support for multiple source files.
* No support for appending to code blocks, only replacing them (will output a warning).
* No support for syntax highlighting natively, although you may use a JavaScript-based solution like [Prism.js](https://prismjs.com/).

## Design Considerations

* Allow code blocks to be written anywhere in the literate program and let NailIt compile them into a program that makes sense, per the Knuthian definition of literate programming.
* Allow flexibility in laying out a literate program.
* Remain compatible with existing Markdown engines, like GitHub's renderer.
* Keep it simple and probably naive.

## Source Code

This README contains NailIt's entire source code! However for convenience and bootstrapping, this repo also provides the sources generated off this README. It also serves as a practical explanation on what literate programs NailIt can process.

To make the compileable source code from this README, do:

```sh
nailit tangle README.md .
```

To generate a literate program as HTML from this README, do:

```sh
nailit weave README.md index.html
```

The program is explained below, though it is still a work-in-progress.

### Entry point

The entry point to the program is about what you'd expect: Parse command line arguments, do stuff accordingly. The really nice `docopt` library is used to transform the command line help string into actual arguments the program can parse. The commands, at least, stay in-sync *and* self-documenting.

```nim main program
let args = """
@{command line arguments}
""".docopt(
  version = "NailIt 0.2.0"
  )

let blocks =
  open($args["<source.md>"]).getBlocks()

if args["weave"].to_bool():
  @{call weave command}

if args["tangle"].to_bool():
  @{call tangle command}

if args["blocks"].to_bool():
  @{call blocks command}
```

### Blocks

Blocks are just text with attributes that make it either "part of the explanation" or "part of the code". Prose blocks are straight-forward, containing only content. Code blocks however, has additional metadata.

```nim block type definition
BlockType = enum
  Prose
  Code

Block = object
  content: string
  case kind: BlockType
  of Code:
    name: string
    language: string
  else:
    discard
```

#### Parsing blocks from the document

Basically, parsing is done on a line-by-line basis. This function takes in a file input and spits out the list of blocks resulting from that file.

```nim get blocks from source function
proc getBlocks(f: File): seq[Block] =
  @{helper function to add a block}

  var
    totalBlocks: seq[Block] = @[]
    isCodeBlock = false

  var
    contentBuffer = ""
    nextNameBuffer = ""
    nextLangBuffer = ""

  for line in lines(f):
    @{parse a line and make new blocks}

  return totalBlocks
```

While parsing, the program looks for these specific patterns:

* `codeBlockPtn` scans for the start and end of code block *definitions*, in the 4 forms described earlier in this document.
* `codeBlockRefPtn` scans for code block *references*, like `@{named block}`
* `codeBlockRefSpacesPtn` is like `codeBlockRefPtn`, except it grabs whatever leading spaces are in it as well.

```nim regex patterns
codeBlockPtn = re2"^```$|^```(\w+)$|^```(\w+)\s+(.+)$|^```\s+(.+)$"
codeBlockRefPtn = re2"(@\{(.+)\})"
codeBlockRefSpacesPtn = re2"(?m)^(\s*?)@\{(.+?)\}"
```

The two types of blocks in the markdown document live separately and cannot be nested, i.e. no code blocks in prose blocks and vice versa, no code blocks within code blocks, etc. On every line, when one of the code block patterns are found, a switch that asks "is the current block a code block?", is toggled.

```nim parse a line and make new blocks
if (var m: RegexMatch2; line.match(codeBlockPtn, m)):
  totalBlocks.addBlock(
    (if isCodeBlock: Code else: Prose),
    contentBuffer,
    nextNameBuffer,
    nextLangBuffer
  )
  # TODO: BUG a blank line in place of this line makes the
  # below line have incorrect indentation
  @{set the name for the next block conditionally}
  @{set the language for the next block conditionally}
  contentBuffer = ""
  isCodeBlock = not isCodeBlock
else:
  contentBuffer &= line & "\n"
```

The nature of this loop means that if a code block begins the document, it will come after an empty prose block. Not that it matters, anyway. Since the code block to be added is not actually inserted until it hits an ending `\`\`\``, setting metadata for that code block is deferred.

The regex library I'm using expresses empty matches by having its begin index greater than the end index, but I wanna be lazy, so here's a helper function.

```nim function to determine if a regex match is empty
proc isEmptyMatch(s: Slice[int]): bool {.inline.} =
  if (s.a > s.b): return true
  return false
```

Groups 2 and 3 contain the name of the new block, so I'll check for both.

```nim set the name for the next block conditionally
nextNameBuffer = (
  if not (m.group(2).isEmptyMatch()): line[m.group(2)].strip()
  elif not (m.group(3).isEmptyMatch()): line[m.group(3)].strip()
  else: ""
)
```

As are the language identifier in groups 0 and 1. Note here that group 0 really means the 0th (first) group, and not "the entire match" as Python would have it.

```nim set the language for the next block conditionally
nextLangBuffer = (
  if not (m.group(0).isEmptyMatch()): line[m.group(0)]
  elif not (m.group(1).isEmptyMatch()): line[m.group(1)]
  else: ""
)
```

This helper function exists to handle things like spaces before and after the content, as well as potentially other issues should they come in the future.

```nim helper function to add a block
proc addBlock(
    blocks: var seq[Block],
    parseAs: BlockType,
    contentBuf: string,
    nameBuf: string = "",
    langBuf: string = ""
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
      ),
      language: langBuf
    )
```

Here's where we trim the spaces. The final line is what will ultimately be the value for `content`. I do like how Nim lets me do this kinda thing.

```nim trim spaces on either end of the content
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

```nim weave function
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

#### Counting code block references

A code block is usually referenced by other code blocks, so for every named code block I need to track how many times they're referenced or invoked in other code blocks. Just in case I need to show it.

```nim initialize code block references list
for txblock in blocks:
  case txblock.kind
  of Code:
    if not reflist.hasKey txblock.name:
      reflist[txblock.name] = initCountTable[string](0)
  of Prose:
    discard
```

For each block I then add 1 to the reference count of each other code block referenced within this code block. Here I can also do some checking, warning you that you might have referenced a block that doesn't even exist at all.

```nim count code block references
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

#### Generating the prose block HTML

Converting prose blocks to HTML is trivial: just use the `rstToHtml` function on the entire input and append it to the HTML. Although there is a bit of a quirk when the contents are not preceded with a blank line: the first paragraph will be text whereas the others would be surrounded in <p>. This can add pain to layout and styling, and so I've put a `.. raw:: html` hack to force the first paragraph to be surrounded in <p>.

```nim convert a prose block into html
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

#### Generating the code block HTML

On the other hand, converting code blocks aren't so trivial. At minimum the code block needs to have escapes in order for them not to be interpreted as HTML code when I don't want it, which can lead to incorrect code displays. Then there's also the extra metadata that needs to be laid out so as to easily identify and navigate between them.

```nim convert a code block into html
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

First I escape the common HTML characters, and then turn all code block references into links.

```nim make the code block html-friendly
txblock.content
  .replace("&", "&amp;")
  .replace("<", "&lt;")
  .replace(">", "&gt;")
  .replace(codeBlockRefPtn, nameAsLink)
```

The link-replacement is done by this helper function:

```nim helper function to transform names to links
proc nameAsLink(m: RegexMatch2, s: string): string =
  return
    "</code><code class=\"cb-reference\"><a href=\"#" &
      s[m.group(1)].normalize() &
    "\">" &
      s[m.group(0)] &
    "</a></code><code class=\"cb-content\">"
```

Every one of these links needs to refer to valid HTML identifiers, which, to make it consistent, I'll have to make a helper function to convert from the code block's name to a weird HTML identifier.

```nim function to normalize labels
proc normalize(s: string): string =
  return s
    .replace("_","")
    .replace(" ","")
    .tolowerascii()
```

After I've converted the main content into something presentable, I can wrap it in an HTML container, having a title tab if the code block has a name, but a plain pre otherwise. In them I also add language information via a class, so that external tools or JavaScript would know what to do with them.

```nim code block html start
if txblock.name.len > 0:
  @{starting html for named code block}
else:
  @{starting html for anonymous code block}
```

```nim starting html for named code block
"<div class=\"code-block" & (
    if txblock.language.strip() == "": ""
    else: " language-" & txblock.language
  ) & "\" id=\"" & normName & "\">" &
  "<header class=\"block-title\">" &
    "<a href=\"#" & normName & "\">" & txblock.name & "</a>" &
  "</header>" &
  "<pre><code class=\"cb-content\">" &
    escapedCode &
  "</code></pre>"
```

```nim starting html for anonymous code block
"<div class=\"code-block" & (
  if txblock.language.strip() == "": ""
  else: " language-" & txblock.language
) & "\">" &
  "<pre><code class=\"cb-content\">" &
    escapedCode &
  "</code></pre>"
```

```nim code block html end
"</div>"
```

The backlinks list take advantage of the whole block reference-counting thing from earlier. It can help navigate back and forth between sections of code, answering the question of "Hmm, where is *this* used?"

```nim generate backlinks list for html code block
generatedHtml &= "<footer class=\"used-by\">Used by "

for i in reflist[txblock.name].keys:
  let normI = i.normalize()
  generatedHtml &=
    "<a href=\"#" & normI & "\">" & i &
    # " &times; " & $(reflist[txblock.name][i]) &
    "</a> "
generatedHtml &= "</footer>"
```

#### Preparing the HTML output

What I have so far is the raw HTML of every block, now I just have to wrap it into a useable HTML document. And for this I'll want a template approach. The template must have both `<!-- TITLE -->` and `<!-- BODY -->` for it to be useable. If a template is not provided, it will just fall back onto a minimal, default one.

```nim insert weaved into html template
proc intoHtmlTemplate(weaved: string, inputTemplate: string = "", title: string = ""): string =
  const defaultTemp = staticRead("default.html")

  let temp = (
    if inputTemplate.strip() == "": defaultTemp
    else: inputTemplate
  )

  # <!-- TITLE --> is replaced with the source file name.
  # <!-- BODY --> is replaced with the body of the document.
  # The spellings need to exact.

  return temp.replace("<!-- TITLE -->", title).replace("<!-- BODY -->", weaved)
```

This is the default HTML template, you can find it in the source under `src/default.html`. For styling, it assumes a `css/screen.css` and `css/print.css` to be available from the point of view of the rendered HTML file.

```html /src/default.html
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title><!-- TITLE --></title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="css/screen.css" media="screen,projection,tv">
    <link rel="stylesheet" href="css/print.css" media="print">
  </head>
  <body>
    <!-- BODY -->
  </body>
</html>
```

#### Calling the weave command

From the main program entry point, the `weave` command supports supplying a template file via the option `--template`. This is optional, as the command has a "default" template that it uses.

```nim call weave command
let weaved = blocks.weave().intoHtmlTemplate(
  inputTemplate = (
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

Meanwhile, `tangle` here exports files from the literate program to make source code that can be compiled. It needs to do two things:

1. Replace code block references with the actual code blocks.
2. Save code blocks to files when it's warranted to do so.

```nim tangle function
proc tangle(blocks: seq[Block], dest: string) =
  var codeBlkMap: Table[string, string]

  @{helper function to replace references with content}

  @{fill code block mappings}
  @{modify code block mappings with actual values}
  @{save code block to files}
```

#### Replacing code block references

First I'll want to go through every code block in document order and populate the code block mappings with the contents of their respective code blocks verbatim. There's no "append" feature, but there is a "replace" feature (no special syntax required), which will warn you when you're replacing a block.

```nim fill code block mappings
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

Then I'll go through the code block mappings again to replace the references with the actual content. Er, uh… this should probably be done recursively, but for small code stuff I think it works alright for now.

```nim modify code block mappings with actual values
for codeBlk in codeBlkMap.mvalues: # :(
  for _ in 0 .. codeBlk.findAll(codeBlockRefSpacesPtn).len: # :(
    codeBlk = codeBlk.replace(codeBlockRefSpacesPtn, replaceReferencesWithContent)
```
The references are replaced in such a way that it retains the leading spaces used for the reference in every line of the replacement. For example, if a reference `@{something}` starts with 4 spaces, the entire thing to replace it will start every line with an additional 4 spaces. I think this can help in whitespace-sensitive languages by ensuring you don't accidentally change the indentation inside of a loop or something.

```nim helper function to replace references with content
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

#### Saving to files

NailIt will only save to files code blocks which start with a `/`. The `/` here means "your current working directory or your specified user directory."

```nim save code block to files
for key in codeBlkMap.keys:
    if key.len > 0 and key[0] == '/':
      let outFileName = [dest, key[1 ..^ 1]].join($os.DirSep)
      outFileName.parentDir.createDir()
      outFileName.open(fmWrite).write(codeBlkMap[key])
      stderr.writeLine "INFO: wrote to file " & outFileName.string
```

#### Calling the tangle command

```nim call tangle command
blocks.tangle(($args["<destdir/>"]))
quit(0)
```

### View Blocks

This `blocks` command is really just a debugging tool. It answers the question of "What does NailIt actually see when I give it my literate program?"

```nim blocks function
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
        of Code: " \"" & b.name & "\" (" & b.language & ")"
      )
    echo '-'.repeat(blockTitle.len)
    echo blockTitle
    echo '-'.repeat(blockTitle.len)
    num += 1
    echo b.content
    echo '-'.repeat(blockTitle.len) & '\n'
```

#### Calling the view blocks function

```nim call blocks command
blocks.displayBlocks()
```

### Overall program structure

Finally, let's put this all together into the full code for the thing.

```nim /src/nailit.nim
@{imports}
@{types}
@{constants}
@{functions}

when is_main_module:
  @{main program}
```

```nim imports
import regex
import std/[strutils, tables, strtabs, os]
import packages/docutils/[rst, rstgen]
import docopt
```

```nim types
type
  @{block type definition}
```

```nim constants
const
  @{regex patterns}
```

```nim functions
@{function to normalize labels}

@{function to determine if a regex match is empty}

@{get blocks from source function}

@{weave function}

@{tangle function}

@{insert weaved into html template}

@{blocks function}
```
