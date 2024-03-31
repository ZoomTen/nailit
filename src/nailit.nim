import regex
import std/[strutils, tables, strtabs, os]
import packages/docutils/[rst, rstgen]
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
      language: string
    else:
      discard
const
  codeBlockPtn = re2"^```$|^```(\w+)$|^```(\w+)\s+(.+)$|^```\s+(.+)$"
  codeBlockRefPtn = re2"(@\{(.+)\})"
  codeBlockRefSpacesPtn = re2"(?m)^(\s*?)@\{(.+?)\}"
proc normalize(s: string): string =
  return s
    .replace("_","")
    .replace(" ","")
    .tolowerascii()

proc isEmptyMatch(s: Slice[int]): bool {.inline.} =
  return (s.a > s.b)

proc getBlocks(f: File): seq[Block] =
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
          var contentStripped = contentBuf
          
          if contentStripped.len == 1:
            contentStripped = ""
          else:
            if contentStripped[0] == '\n':
              contentStripped = contentStripped[1 ..^ 1]
            if contentStripped[^1] == '\n':
              contentStripped = contentStripped[0 ..^ 2]
          
          contentStripped

        ),
        language: langBuf
      )


  var
    totalBlocks: seq[Block] = @[]
    isCodeBlock = false

  var
    contentBuffer = ""
    nextNameBuffer = ""
    nextLangBuffer = ""

  for line in lines(f):
    if (var m: RegexMatch2; line.match(codeBlockPtn, m)):
      totalBlocks.addBlock(
        (if isCodeBlock: Code else: Prose),
        contentBuffer,
        nextNameBuffer,
        nextLangBuffer
      )
      # TODO: BUG a blank line in place of this line makes the
      # below line have incorrect indentation
      nextNameBuffer = (
        if not (m.group(2).isEmptyMatch()): line[m.group(2)].strip()
        elif not (m.group(3).isEmptyMatch()): line[m.group(3)].strip()
        else: ""
      )

      nextLangBuffer = (
        if not (m.group(0).isEmptyMatch()): line[m.group(0)]
        elif not (m.group(1).isEmptyMatch()): line[m.group(1)]
        else: ""
      )

      contentBuffer = ""
      isCodeBlock = not isCodeBlock
    else:
      contentBuffer &= line & "\n"


  return totalBlocks

proc weave(blocks: seq[Block]): string =
  var reflist: Table[string, CountTable[string]]
  var generatedHtml = ""
  for txblock in blocks:
    case txblock.kind
    of Code:
      if not reflist.hasKey txblock.name:
        reflist[txblock.name] = initCountTable[string](0)
    of Prose:
      discard

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

  proc nameAsLink(m: RegexMatch2, s: string): string =
    return
      "</code><code class=\"cb-reference\"><a href=\"#" &
        s[m.group(1)].normalize() &
      "\">" &
        s[m.group(0)] &
      "</a></code><code class=\"cb-content\">"


  # turn each block to stuff
  for txblock in blocks:
    case txblock.kind
    of Code:
      let escapedCode =
        txblock.content
          .replace("&", "&amp;")
          .replace("<", "&lt;")
          .replace(">", "&gt;")
          .replace(codeBlockRefPtn, nameAsLink)
      
      
      let normName = txblock.name.normalize()
      
      # start writing converted code block
      generatedHtml &= (
        if txblock.name.len > 0:
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
      
        else:
          "<div class=\"code-block" & (
            if txblock.language.strip() == "": ""
            else: " language-" & txblock.language
          ) & "\">" &
            "<pre><code class=\"cb-content\">" &
              escapedCode &
            "</code></pre>"
      
      
      )
      
      # if the block is used somewhere else, say so
      if txblock.name.len > 0 and reflist[txblock.name].len > 0:
        generatedHtml &= "<footer class=\"used-by\">Used by "
        
        for i in reflist[txblock.name].keys:
          let normI = i.normalize()
          generatedHtml &=
            "<a href=\"#" & normI & "\">" & i &
            # " &times; " & $(reflist[txblock.name][i]) &
            "</a> "
        generatedHtml &= "</footer>"
      
      
      # end write block
      generatedHtml &= (
        "</div>"
      
      )

    of Prose:
      let toParaHack = ".. raw:: html\n\n" & txblock.content
      generatedHtml &=
        toParaHack.rstToHtml(
          {
            roSupportMarkdown, roPreferMarkdown, roSandboxDisabled,
            roSupportRawDirective,
          },
          modeStyleInsensitive.newStringTable(),
        )

  return generatedHtml

proc tangle(blocks: seq[Block], dest: string) =
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

  for txblock in blocks:
    case txblock.kind
    of Code:
      if txblock.name.len < 1: continue
      if codeBlkMap.hasKey txblock.name:
        stderr.writeLine "WARNING: replacing code block " & txblock.name
      codeBlkMap[txblock.name] = txblock.content
    of Prose:
      discard

  for codeBlk in codeBlkMap.mvalues: # :(
    for _ in 0 .. codeBlk.findAll(codeBlockRefSpacesPtn).len: # :(
      codeBlk = codeBlk.replace(codeBlockRefSpacesPtn, replaceReferencesWithContent)

  for key in codeBlkMap.keys:
    if key.len > 0 and key[0] == '/':
      let outFileName = [dest, key[1 ..^ 1]].join($os.DirSep)
      outFileName.parentDir.createDir()
      outFileName.open(fmWrite).write(codeBlkMap[key])
      stderr.writeLine "INFO: wrote to file " & outFileName.string


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

when is_main_module:
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
    version = "NailIt 0.2.0"
    )
  
  let blocks =
    open($args["<source.md>"]).getBlocks()
  
  if args["weave"].to_bool():
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

  
  if args["tangle"].to_bool():
    blocks.tangle(($args["<destdir/>"]))
    quit(0)

  
  if args["blocks"].to_bool():
    blocks.displayBlocks()

