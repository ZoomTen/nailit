# NailIt - a simple literate programming tool.

# LIMITATION: Each code block surrounded by ``` MUST have a name.
#             Will crash when regular nameless code blocks are used.

import regex
import std/[strutils, tables, strtabs, paths, os]
import packages/docutils/[rst, rstgen, dochelpers]
import docopt

# import print

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

        if contentStripped[0] == '\n':
          contentStripped = contentStripped[1 ..^ 1]
        if contentStripped[^1] == '\n':
          contentStripped = contentStripped[0 ..^ 2]

        contentStripped
      ), # return value
    )

## Parse blocks from a file.
## 
## Code blocks begin with ``` <name>
## Code blocks end with ```
## 
## The other kind of block are Prose blocks,
## which is everything else in the file, and
## is treated as Nim's weird RST+MD combination.
proc getBlocks(f: File): seq[Block] =
  var totalBlocks: seq[Block] = @[]
  var contentBuffer = ""
  var nameBuffer = ""
  var flushed = false

  for line in lines(f):
    if (var m: RegexMatch2; line.match(re2"^```\s+(.+)", m)):
      # the line after this must be a code block
      totalBlocks.addBlock Prose, contentBuffer # commit the previous block
      contentBuffer = ""
      nameBuffer = line[m.group(0)]
      flushed = true
    elif line.strip() == "```": # the line after this must be a prose block
      totalBlocks.addBlock Code, contentBuffer, nameBuffer # commit the previous block
      contentBuffer = ".. raw:: html\n" # hack
      flushed = true
    else:
      flushed = false
      contentBuffer &= line & "\n"

  if not flushed:
    totalBlocks.addBlock Prose, contentBuffer

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
      for m in txblock.content.findAll(re2"@\{(.+)\}"):
        let keyName = txblock.content[m.captures[0]]
        if reflist.hasKey keyName:
          reflist[keyName].inc txblock.name
        else:
          debugEcho "WARNING: key " & keyName & " not found!"
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
        .replace(re2"(@\{(.+)\})", nameAsLink)
      let normName = txblock.name.nimIdentBackticksNormalize()

      # start writing converted code block
      generatedHtml &=
        "<div class=\"code-block\" id=\"" & normName &
        "\"><a class=\"block-title\" href=\"#" & normName & "\">" & txblock.name &
        "</a><pre><code>" & escapedCode & "</code></pre>"

      # if the block is used somewhere else, say so
      if reflist[txblock.name].len > 0:
        generatedHtml &= "<span class=\"used-by\">Used by "
        for i in reflist[txblock.name].keys:
          let normI = i.nimIdentBackticksNormalize()
          generatedHtml &=
            "<a href=\"#" & normI & "\">" & i &
            # " &times; " & $(reflist[txblock.name][i]) &
            "</a> "
        generatedHtml &= "</span>"

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
  codeBlkMap.clear()

  proc replaceReferencesWithContent(m: RegexMatch2, s: string): string =
    let keyName = s[m.group(1)]
    if codeBlkMap.hasKey keyName:
      # indent each line with the same amout of spaces as
      # the indentation of the references
      if (let initialSpaces = s[m.group(0)].replace("\n", ""); initialSpaces.len > 0):
        var paddedCodeLines = "\n" & initialSpaces
        var isInitialLine = true
        for line in codeBlkMap[keyName].strip().splitLines():
          if isInitialLine:
            paddedCodeLines &= line & "\n"
            isInitialLine = false
          else:
            paddedCodeLines &= initialSpaces & line & "\n"
        #print paddedCodeLines
        return paddedCodeLines
      #print codeBlkMap[keyName]
      return s[m.group(0)] & codeBlkMap[keyName]
    else:
      debugEcho "WARNING: key " & keyName & " not found!"
      return "; " & s # ; should be a comment line

  # fill codeblock mappings
  for txblock in blocks:
    case txblock.kind
    of Code:
      if codeBlkMap.hasKey txblock.name:
        debugEcho "Warning: replacing code block " & txblock.name
      codeBlkMap[txblock.name] = txblock.content
    of Prose:
      discard

  # modify the mappings with actual values
  for codeBlk in codeBlkMap.mvalues: # :(
    var count = 0
    for _ in codeBlk.findAll(re2"(\s+?)@\{(.+?)\}"):
      count += 1
    for _ in 0 .. count: # :(
      codeBlk = codeBlk.replace(re2"(\s+?)@\{(.+?)\}", replaceReferencesWithContent)

  for key in codeBlkMap.keys:
    if key[0] == '/':
      let outFileName = dest / Path(key[1 ..^ 1])
      outFileName.parentDir.string.createDir()
      outFileName.string.open(fmWrite).write(codeBlkMap[key])

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

when isMainModule:
  let args = """
  NailIt - a simple literate programming tool.

  Usage:
    nailit weave [--template=<template.html>] <source.md> [<out.html>]
    nailit tangle <source.md> <destdir/>
    nailit (-h | --help)
    nailit --version
  
  weave = generate a human-readable HTML document
          from literate programs.
  
  tangle = generate compileable source code from
           literate programs.
  """.docopt(
    version = "NailIt 0.1"
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
