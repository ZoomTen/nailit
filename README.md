# NailIt

A quite minimal [literate programming](http://www.literateprogramming.com/) tool, capable of formatting code with documentation, linking to sections of code and backreferencing other sections of code.

The tool converts from a Markdown file into HTML, fit for reading online or printing, if you want.

The tool supports converting only one Markdown file at the moment, if you want to use multiple files you'll have to combine them somehow… `cat *.md > onesource.md`?

Also, the tool does not at the moment support appending or changing code blocks "dynamically", so you have to uh… *nail it* I guess. It may be better that way, anyway.

## Building

Requires [Nim](https://nim-lang.org/) 2.x. The standard distribution should include the `nimble` tool, use `nimble build` to make a binary.


## Usage

```
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
```

## Structure

Documents are made up of **code blocks** and **prose blocks**.

To make a code block, surround code with a single line of \`\`\` before and after, with the preceding \`\`\` line containing the title as so: **\`\`\` Title of code block.**

Code block titles that start with a `/` will be interpreted as file output relative to the `destdir` specified when calling the program.

Code blocks without a title will—at present—cause the program to crash.

Everything else outside of code blocks are considered **prose blocks** and will be formatted as Markdown… [Nim-flavored Markdown](https://nim-lang.org/docs/markdown_rst.html), at least.

Inside a code block, you can refer to other code blocks like so: **@{Name of other code block}**. Indenting these references will add indentation to the inserted code block when tangling it, so you must keep that in mind when using whitespace-sensitive languages.

Refer to `testDoc/test.md` for an example.
