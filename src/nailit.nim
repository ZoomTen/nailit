# NailIt - a simple literate programming tool.

# LIMITATIONS: @{code block references} must be on
#              a single line

import regex
import std/[strutils, tables, strtabs, paths, os]
import packages/docutils/[rst, rstgen, dochelpers]
import docopt

type
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

const
  codeBlockPtn = re2"^```(\s*(.+))?"
  codeBlockRefPtn = re2"(@\{(.+)\})"
  codeBlockRefSpacesPtn = re2"(?m)^(\s*?)@\{(.+?)\}"

## Helper proc to process and insert blocks in the block list
proc addBlock(
    blocks: var seq[Block], parseAs: BlockType, contentBuf: string, nameBuf: string = ""
) =
  case parseAs
  of Prose:
    blocks.add Block(kind: Prose, content: "\n" & contentBuf)
  of Code:
    blocks.add Block(
      kind: Code,
      name: nameBuf,
      content: (
        var
          # value is the result of an expression
          # try to strip the any start and ending newlines (limited to 1 for now) 
          contentStripped = contentBuf

        if contentStripped.len == 1:
          contentStripped = ""
        else:
          if contentStripped[0] == '\n':
            contentStripped = contentStripped[1 ..^ 1]
          if contentStripped[^1] == '\n':
            contentStripped = contentStripped[0 ..^ 2]

        contentStripped
      ), # return value
    )

## Parse blocks from a file.
##
## Code blocks may have names, but generally
## they start and end with ```.
##
## To give a code block a name, you do ``` <name>
##
## The other kind of block are Prose blocks,
## which is everything else in the file, and
## is treated as Nim's weird RST+MD combination.
proc getBlocks(f: File): seq[Block] =
  var
    totalBlocks: seq[Block] = @[]
    isCode = false

  var
    contentBuffer = ""
    nextNameBuffer = ""

  for line in lines(f):
    if (var m: RegexMatch2; line.match(codeBlockPtn, m)):
      totalBlocks.addBlock((if isCode: Code else: Prose), contentBuffer, nextNameBuffer)

      nextNameBuffer = (
        if (m.group(1).a > -1) and (m.group(1).b > -1):
          line[m.group(1)]
        else: ""
      )
      contentBuffer = ""
      isCode = not isCode
    else:
      contentBuffer &= line & "\n"

  return totalBlocks

## Compile an HTML page from a literate program.
proc weave(blocks: seq[Block]): string =
  var reflist: Table[string, CountTable[string]]
  var generatedHtml = ""

  # for each block, count how many times it's referenced
  # ensure all seqs are defined first
  for txblock in blocks:
    case txblock.kind
    of Code:
      if not reflist.hasKey txblock.name:
        reflist[txblock.name] = initCountTable[string](0)
    of Prose:
      discard

  # do count
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

  # then, generate the HTML file

  # the header should be a link to itself so it can be linked somewhere else
  proc nameAsLink(m: RegexMatch2, s: string): string =
    return
      "<a href=\"#" & s[m.group(1)].nimIdentBackticksNormalize() & "\">" & s[m.group(0)] &
      "</a>"

  # turn each block to stuff
  for txblock in blocks:
    case txblock.kind
    of Code:
      # TODO: make it convert properly...
      let escapedCode = txblock.content
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace(codeBlockRefPtn, nameAsLink)
      let normName = txblock.name.nimIdentBackticksNormalize()

      # start writing converted code block
      generatedHtml &=
        "<div class=\"code-block\" id=\"" & normName &
        "\"><header class=\"block-title\"><a href=\"#" & normName & "\">" & txblock.name &
        "</a></header><pre><code>" & escapedCode & "</code></pre>"

      # if the block is used somewhere else, say so
      if reflist[txblock.name].len > 0:
        generatedHtml &= "<footer class=\"used-by\">Used by "
        for i in reflist[txblock.name].keys:
          let normI = i.nimIdentBackticksNormalize()
          generatedHtml &=
            "<a href=\"#" & normI & "\">" & i &
            # " &times; " & $(reflist[txblock.name][i]) &
            "</a> "
        generatedHtml &= "</footer>"

      # end write block
      generatedHtml &= "</div>"
    of Prose:
      # just convert it wholesale
      generatedHtml &=
        txblock.content.rstToHtml(
          {
            roSupportMarkdown, roPreferMarkdown, roSandboxDisabled,
            roSupportRawDirective,
          },
          modeStyleInsensitive.newStringTable(),
        )
  return generatedHtml

## Compile source code files from a literate program.
proc tangle(blocks: seq[Block], dest: Path) =
  var codeBlkMap: Table[string, string]

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

  # fill codeblock mappings
  for txblock in blocks:
    case txblock.kind
    of Code:
      if codeBlkMap.hasKey txblock.name:
        stderr.writeLine "WARNING: replacing code block " & txblock.name
      codeBlkMap[txblock.name] = txblock.content
    of Prose:
      discard

  # modify the mappings with actual values
  for codeBlk in codeBlkMap.mvalues: # :(
    for _ in 0 .. codeBlk.findAll(codeBlockRefSpacesPtn).len: # :(
      codeBlk = codeBlk.replace(codeBlockRefSpacesPtn, replaceReferencesWithContent)

  for key in codeBlkMap.keys:
    if key[0] == '/':
      let outFileName = dest / Path(key[1 ..^ 1])
      outFileName.parentDir.string.createDir()
      outFileName.string.open(fmWrite).write(codeBlkMap[key])
      stderr.writeLine "INFO: wrote to file " & outFileName.string

proc intoHtmlTemplate(weaved: string, temp: string = "", title: string = ""): string =
  if temp.strip() == "":
    return
      """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>""" &
      title &
      """</title>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <link rel="stylesheet" href="css/screen.css" media="screen,projection,tv">
      <link rel="stylesheet" href="css/print.css" media="print">
    </head>
    <body>
    """ &
      weaved &
      """
    </body>
    </html>
    """
  else:
    # <!-- TITLE --> is replaced with the document title.
    # <!-- BODY --> is replaced with the body of the document.
    # The spellings need to exact.
    return temp.replace("<!-- TITLE -->", title).replace("<!-- BODY -->", weaved)

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

when isMainModule:
  let args = """
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
  """.docopt(
    version = "NailIt 0.2"
  )

  let blocks = open($args["<source.md>"]).getBlocks()

  if args["weave"].to_bool():
    # run weave
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

  if args["tangle"].to_bool():
    blocks.tangle(($args["<destdir/>"]).Path())
    quit(0)

  if args["blocks"].to_bool():
    blocks.displayBlocks()
