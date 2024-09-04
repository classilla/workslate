# Programming the Convergent Workslate

[Another Old VCR Accessory After The Fact!](https://oldvcr.blogspot.com/2024/09/programming-convergent-workslates.html)

Copyright 2024 Cameron Kaiser.  
All rights reserved.  
Released under the Floodgap Free Software License.

## What it's for

The WK-100 Convergent WorkSlate ([here's more history and discussion](https://oldvcr.blogspot.com/2024/09/programming-convergent-workslates.html); [here's more technical information](http://www.floodgap.com/retrobits/workslate/)) is a 1983 slab portable computer based on the 8-bit Hitachi 6303 (a Motorola 6800 family CPU) where everything is a spreadsheet, modeled substantially but not completely on Microsoft Multiplan. It was designed by Convergent Technologies in Silicon Valley and produced for just seven months; only a few thousand were sold, causing Convergent to write off over $8 million in losses. The unit weighs less than three pounds and is the size of a US Letter page, 1" thick. In its 16K of memory, it can hold up to 12,868 bytes of spreadsheet data in five separate worksheets displayed on a 46x16 character non-backlit LCD, and can run for up to ten hours on alkaline AA batteries (or longer with modern AA lithiums). It has a built-in microcassette deck that can record voice or data and a 300bps modem. It can be paired with a printer/plotter (the WP-100 MicroPrinter) or a combination serial/parallel expansion box (the WC-100 CommPort), or connected directly to another WorkSlate, all using the 8P8C GPIO "Peripherals" port.

Because it's a spreadsheet, it has a set of unusual built-in functions that support not only typical financial, arithmetic and statistical operations, but it also has phone dialing, date-and-time alarm setting, primitive graphing and even telecommunications via the modem or the GPIO port. It is intentionally not Turing-complete, but applications can be written for it anyway, which Convergent sold on microcassette as Taskware.

## What it is, what it has

This project contains the "WorkSlate Spreadsheet Crossassembler," or WSSC (`wssc.pl`), a Perl script that takes a text file containing data, formulas and directives and emits sheet data you can upload directly to the WorkSlate. It also has three demonstration programs:

  * A Rock-Paper-Scissors game, in the `rps/` directory. `rps.w` contains the WSSC source and `rps.ws` is ready to upload. Enter your moves as numbers in column A, starting in cell A1 (values as instructed onscreen), and the computer will play in column B. Change the random seed for different computer moves (use 4 digit numbers or longer). The winner is determined after three rows; clear column A to play again.
  * A simple pie chart, in the `pie/` directory. The source was generated by the Perl script `piegen.pl`, which takes the radius as an argument. `pie6.w` is generated WSSC source using a radius of 6 (effective on-screen radius of around 6.67) and `pie6.ws` is ready to upload. Enter a percentage into A1 and the WorkSlate will plot it.
  * An Internet gopher client (`gopher.pl`) that uses a connected computer as a proxy. This is a complete example that uses `serport.c` to interface with a connected WorkSlate via the GPIO port ([here's how to wire up this connection](http://www.floodgap.com/retrobits/workslate/)). Compile `serport.c` (it only needs POSIX `termios`) and start the client with `./serport 9600 /path/to/your/serial/port perl gopher.pl`, then start Terminal on the WorkSlate and follow the prompts. You must respond to sheet download requests within five seconds. Menu options are selected with Special-Do It; it is recommended you reduce the size of the Terminal window to four lines instead of the default seven. Screen photographs and a video are [in this blog post](https://oldvcr.blogspot.com/2024/09/programming-convergent-workslates.html).

## How you work it

Provide it WSSC source as a filename option or on standard input, and it will emit a ready-to-upload sheet on standard output. WSSC is a single pass "assembler."

WSSC source files consist of cell data. Cells may appear in any order and are automatically sorted for you. Cell definitions consist of the cell reference, an optional width, and then either a constant or a formula followed by an optional attribute. Cell references are in VisiCalc A1 format, and range from A-Z and AA-DX (i.e., 128) columns and 1-128 rows.

Blank lines and leading and trailing whitespace are ignored, and lines starting with a `#` are treated as comments and removed from the output.

You cannot define the same cell twice, you must define at least one cell, and by default any sheet expected to exceed the WorkSlate's default memory capacity will cause an error (though this is configurable, see below).

If you `chmod +x wssc.pl` and run it directly (e.g., `./wssc.pl`), or run it with Perl with the `-s` option (e.g., `perl -s wssc.pl`), prior to the filename you can pass these options:

  * `-fwidth=[width of first column]`. This is the same as the `.fwidth` pseudo-op, and sets the default width of the first column A. By default this value is 13. Values between 1 and 40 inclusive are valid.
  * `-dwidth=[width of other columns]`. This is the same as the `.dwidth` pseudo-op, and sets the default width of all other columns. By default this value is 9. Values between 1 and 40 inclusive are valid.
  * `-sheet="namename"`. This is the same as the `.worksheet` pseudo-op, and sets the sheet name. It must be exactly eight characters (pad it with spaces if it's shorter, hence the quotation marks). By default, its name is ` empty  `, with one space before and two after.
  * `-include_mem`. By default, since WSSC does not yet compute accurate formula memory usage, WSSC sets the memory slot of the emitted spreadsheet to zero (which is valid). If you want to include its estimate anyway, pass this option.
  * `-wbig_file`. WSSC will raise an error if the expected size will be too large for a 16K WorkSlate. If you believe that the spreadsheet will assemble to a smaller size than WSSC is estimating, pass this option. (WSSC could still be right.)
  * `-wno_warn_width`. By default, WSSC will warn you if you are defining a column width in the current cell, but previous cells in that column were using the default width (i.e., didn't specify a width). This option suppresses the warning.
  * `-wwarn_default_width`. If a column was previously defined with a width, successive cells in that column inherit it by default. This will display a warning when that happens.

### Constants

Here are examples of constants, showing numbers, integers, negative decimals (all stored as floating point), strings, and dates and times (both special types of number).

```
A1-3.14159
A2-895
A3--.202
BC35-"Hello World"
J4-9/5/2024
W80-8:32pm
```

Double quotes can be embedded directly in a string constant without escaping them.

### Special characters (tilde sequences)

Lines may contain tilde (`~ ~`) sequences to enter special characters (`~~` is a literal tilde). The character on the top row (these characters are modern Unicode approximations) is emitted by the character on the bottom row between tildes.

&#x2190; | &#x2192; | &#x1f4fc; | &#x26b7; | &times; | &divide; | &ne; | &#x1f514; | &#x1f4de; | &#x23f2; | `␊` | &#x25c0; | `␌` | `␍` | ┏ | ┓ | ┗ | ┛ | ┼ | ┬ | ┴ | ├ | ┤ | ┃ | ━ | ═ | █ | `␛`| ᶜₜ | ▄ | ▐ | □
--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--|--
[space] | !| " | # | $ | % | & | ' | ( | ) | *| + | , | - | . | / | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | : | ; | < | = | > | ?

### Formulas

Formulas are formatted according to the WorkSlate Reference Guide (if you don't have this book, here is a [list of built-in functions and basic syntax](http://www.floodgap.com/retrobits/workslate/)). Remember that the WorkSlate uses &times; and &divide;, not * and /. These and all other special characters (q.v.) should be rendered in tilde sequences. Here are some examples:

```
A2=Total(A5...C8)
M20=(B5+61)~%~@B6
T33=Average(A1,A2,A9...A12)
L17=Max(A1,99)+Min(A2...A5,-1)
G2=WaitFor("*")+Send("OK~-*~")
CM91=If(And(A3<15,A4>A6),"Valid",If(Not(A3=5),"Invalid","Error"))
```

### Width and cell attributes

An optional width can be specified for any cell, either a constant or formula, between 1 and 40 characters inclusive. If a cell doesn't specify a width, it either uses the defaults (see _Pseudo-ops_ or the `-fwidth` and `-dwidth` options) or the width of any previously defined cell in its column. Width is per column, so if a conflict is detected, WSSC will throw an error. Here is an example that only uses default widths:

```
A1-"Hello"
B1-"World"
C1-999
D1=C1-5
```

The first line of this example sets column A to width 15. Since the next cell in column A doesn't give a width, it gets the same previously defined width. (If `-wwarn_default_width` is passed to WSSC, this will cause a warning.)

```
A1.15-"Hello"
A2-"World"
```

This next example causes an error, because column A was already defined as width 15:

```
A1.15-"Hello"
A2.5-"World"
```

See also the `-wno_warn_width` option.

Attributes are single characters attached to the end of the cell, after a space. They are "D"ecimal (for rounded dollar amounts), "W"hole (for rounded integers), "L"eft justification (by default for strings), "R"ight justification (by default for numbers), and "O"verlap for wide cells that exceed the width of their column. At most one of "D" and "W" may be combined with at most one "L", "R" or "O" (the latter appears first). Attributes may be applied to both formulas and constants, and can be used with widths. Here are some examples:

```
A1.15-"Hello" R
B3=Date(0)+365 L
D1-3.14159 D L
```

### Pseudo-ops

The following are pseudo-ops and appear by themselves on a line.

  * `.dwidth [value]`. This sets the default width of all other columns but the first (between 1 and 40 inclusive). This is the same as the `-dwidth` option and has the same default of 9, but this pseudo-op will override anything on the command line. If set multiple times in a source file, the last definition is used.
  * `.fwidth [value]`. This sets the default width of the first column A (between 1 and 40 inclusive). This is the same as the `-fwidth` option and has the same default of 13, but this pseudo-op will override anything on the command line. If set multiple times in a source file, the last definition is used.
  * `.startcell [cell reference]`. This sets the default cell for the cursor after the sheet is loaded. It must be a syntactically valid cell reference, but it may contain a cell that is not explicitly defined otherwise. If set multiple times in a source file, the last definition is used.
  * `.worksheet "namename"`. This sets the name of the sheet. This is the same as the `-worksheet` option and takes the same argument (a string exactly eight characters long, padded with spaces), but this pseudo-op will override anything on the command line. The quotation marks are required. If set multiple times in a source file, the last definition is used.

### Things known not to (probably) work

  * The formula memory estimation algorithm is a good heuristic and is usually close, but is usually wrong.
  * It is possible some combinations and syntaxes will be allowed as legal that will nevertheless cause a cell error when loaded.

## Bug reports and pull requests

Bug reports without pull requests may or may not be addressed, ever.

Feature requests without pull requests may be closed or deleted.

Do not submit pull requests to substantially refactor any script without a good reason, or to convert them to another programming language. For those, please fork the project.

## License

WSSC and the demonstration programs, except where noted, are under the Floodgap Free Software License. Please read it.