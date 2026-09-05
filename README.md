# Delphi Uses Analyzer

A console tool that builds a unit dependency graph for a Delphi project.

It starts at the project's `.dpr`, walks every `uses` clause transitively, resolves each
unit name to a file the way the compiler would, and emits the graph as JSON.

It exists to answer questions that are tedious to answer by reading source - starting with
**why is this pulling in a unit I do not want**, and ending with **stop it coming back**.

## Commands

```
DelphiUsesAnalyzer <project> [options]                analyse and report
DelphiUsesAnalyzer why        <project> <unit>        the chains that reach a unit
DelphiUsesAnalyzer references <project> <unit>        the units that reference a unit
DelphiUsesAnalyzer path       <project> <from> <to>   the chains between two units
DelphiUsesAnalyzer deps       <project> <unit>        what a unit pulls in
DelphiUsesAnalyzer cost       <project> [unit]        what each reference costs
DelphiUsesAnalyzer cycles     <project>               units that reference each other
DelphiUsesAnalyzer check      <project> --forbid:...  fail when a rule is broken
DelphiUsesAnalyzer diff       <project> <other>       what changed between two graphs
DelphiUsesAnalyzer help [command]
```

`<project>` is a `.dproj`, a `.dpr`, or a `.json` graph saved earlier with `--output`.
Given a `.dpr`, a sibling `.dproj` is used automatically when there is one - that is where
the search paths live.

`<unit>` is a unit name or a glob. `references` is also spelled `refs`.

Only `check` sets a non-zero exit code, and only when a rule is broken. Everything else
exits 0 unless the command line was wrong or something threw.

### why

```
DelphiUsesAnalyzer why MyApp.dproj Vcl.Graphics
```

```
── Why Vcl.Graphics ────────────────────────────────────────────────────────────
SampleApp
└── SampleApp.Middle program SampleApp.dpr(7)
    └── SampleApp.Inner implementation SampleApp.Middle.pas(13)
        └── Vcl.Graphics interface SampleApp.Inner.pas(7) MSWINDOWS
```

Every hop names the file, the line, which clause it was written in, and any conditional
guarding it. Routes that share their leading units are drawn once, so the tree shows where
they actually diverge - the place worth looking when deciding what to cut.

A glob turns it from a lookup into a survey. `why MyApp.dproj Vcl.*` answers for every VCL
unit at once, grouped by the unit that brings each one in:

```
── Why Vcl.* ───────────────────────────────────────────────────────────────────
33 units match Vcl.* (up to 5 chains each)
MyApp
├── MyApp.Options program MyApp.dpr(31)
│   ├── Vcl.Controls interface MyApp.Options.pas(10)
│   ├── Vcl.Forms interface MyApp.Options.pas(9)
│   └── Vcl.Graphics interface MyApp.Options.pas(12)
├── MyApp.PluginApi program MyApp.dpr(33)
│   └── Vcl.Dialogs implementation MyApp.PluginApi.pas(58)
...
```

`--maxpaths` means chains per matched unit and applies the same either way, so a unit
answers identically whether you ask for it by name or catch it in a glob. On a large
survey that is worth turning down: on one application `why MyApp.dproj Vcl.* --maxpaths:1`
gave one route to each of 33 units in 61 lines, against 223 at the default of 5.

### references

`why` walks from the program down, so a unit named directly in the `.dpr` has a one hop
chain and there is very little to see. `references` asks who uses it, which for a widely
used unit is a rather different answer:

```
── References to Vcl.Forms ─────────────────────────────────────────────────────

Vcl.Forms is referenced 852 times
╭──────────────────────┬───────┬──────────────────────────────╮
│ Unit                 │ Where │ At                           │
├──────────────────────┼───────┼──────────────────────────────┤
│ MyApp.AboutDialog    │ intf  │ MyApp.AboutDialog.pas(12)    │
│ MyApp.MainForm       │ intf  │ MyApp.MainForm.pas(14)       │
│ MyApp.Options.Dialog │ intf  │ MyApp.Options.Dialog.pas(11) │
╰──────────────────────┴───────┴──────────────────────────────╯
... and 849 more, use --limit:0 for all
```

`Where` is the clause the reference was written in - `intf`, `impl` or `prog`.

### path

`why` always starts at the program. `path` starts wherever you like, which is how you ask
whether one part of a project reaches another:

```
DelphiUsesAnalyzer path MyApp.dproj MyApp.Core Vcl.Forms
```

Same tree, different root. The starting unit has to name exactly one unit - a glob that
matches several is a question with no single answer, and it says so rather than picking.

### deps

The mirror of `why`: not how a unit gets pulled in, but what it pulls in.

```
── What SampleApp.Middle pulls in ──────────────────────────────────────────────

SampleApp.Middle pulls in 3 units
SampleApp.Middle
└── SampleApp.Inner implementation SampleApp.Middle.pas(13)
    ├── Vcl.Graphics interface SampleApp.Inner.pas(7) MSWINDOWS
    └── System.Classes interface SampleApp.Inner.pas(9)
```

A dependency graph is not a tree, so drawing one as a tree has to stop somewhere. A unit is
expanded the first time it appears; later appearances are marked `(above)` when there was
something under it, and left alone when there was not. That keeps the output the size of
the graph rather than the size of every route through it.

`--depth` limits how far down it goes and defaults to 3. `--depth:0` is all of it, which on
a real project is long - 1576 lines for one unit of a 275 unit project - so it is worth
piping somewhere you can search.

### cost

How much a dependency is actually worth removing.

```
── What SampleApp uses costs ───────────────────────────────────────────────────

SampleApp
╭───────────────────────┬───────────┬───────┬──────────────────╮
│ Reference             │ Exclusive │ Total │ At               │
├───────────────────────┼───────────┼───────┼──────────────────┤
│ SampleApp.Middle      │         4 │     4 │ SampleApp.dpr(7) │
│ SampleApp.Conditional │         3 │     4 │ SampleApp.dpr(8) │
│ System.SysUtils       │         0 │     1 │ SampleApp.dpr(6) │
╰───────────────────────┴───────────┴───────┴──────────────────╯
Exclusive = units lost from SampleApp if this reference goes
Total = everything that reference reaches
```

`Total` is what that reference reaches. `Exclusive` is what you would actually save, and
the gap between the two is the point: `System.SysUtils` reaches a unit, but deleting the
reference saves nothing because `SampleApp.Conditional` uses it too.

With no unit, `cost <project>` ranks every unit in the graph by what only it brings in.
That is a different question - removing a **unit** rather than one **reference** to it -
and the footnote under each table says which one you are looking at. See Known limits
before reading much into that ranking on a project whose `.dpr` names every unit.

### cycles

Units that reference each other in a circle. Delphi will not compile an interface to
interface cycle, but a circle through an implementation clause is legal, common, and makes
initialization order matter:

```
7 units, the shortest way round being
╭─────────────────────────────────────┬───────┬──────────────────────────╮
│ Uses                                │ Where │ At                       │
├─────────────────────────────────────┼───────┼──────────────────────────┤
│ System.SyncObjs uses System.Classes │ impl  │ System.SyncObjs.pas(591) │
│ System.Classes uses System.Rtti     │ intf  │ System.Classes.pas(79)   │
│ System.Rtti uses System.SyncObjs    │ intf  │ System.Rtti.pas(23)      │
╰─────────────────────────────────────┴───────┴──────────────────────────╯
```

Worst tangle first, each shown as the shortest way round it, so the hop to break is visible
rather than inferred. That example is real, and it is the Delphi RTL.

### check

The one that stops the problem coming back. `check` exits with **code 1** when the project
reaches a unit a rule forbids, so it belongs in a build rather than in a terminal:

```
DelphiUsesAnalyzer check MyApp.dproj --forbid:Vcl.*,Fmx.* --limit:3
```

```
── Checking MyApp.dproj ────────────────────────────────────────────────────────
FAIL  Vcl.* - 33 units reach it
      Vcl.Controls via MyApp.Options MyApp.dpr(31)
      Vcl.Dialogs via MyApp.PluginApi MyApp.dpr(33)
      Vcl.Forms via MyApp.Options MyApp.dpr(31)
      ... and 30 more, use --limit:0 for all
PASS  Fmx.*

1 of 2 rules failed
```

Each rule is reported on its own whether it caught anything or not, and each offending unit
is shown with the first step out of the program - the line to go and look at. Only units
the program actually reaches count; a unit sitting in the graph that nothing reaches is not
a dependency and will not fail anyone's build.

Rules can live in a file, one unit name or glob per line, which is the version you check in
next to the `.dproj`:

```
# no gui in a console app
Vcl.*
Fmx.*
!Vcl.Graphics      # the printer code needs TCanvas
Winapi.ShellAPI
```

A bare line forbids. `!` in front of one is an exception, and an exception beats a
forbidding rule wherever either was written. `#` and `//` start a comment. That is the
whole grammar - a line with a space in the middle is refused, with its line number, because
it is almost always someone writing in a syntax this does not have.

`--rules:<file>`, `--forbid:` and `--allow:` can be used together; the rules add up.

### diff

What changed between two graphs. Either side may be a `.dproj`, a `.dpr` or a saved
`.json`, so a graph saved before a refactor can be compared against the live project:

```
DelphiUsesAnalyzer diff before.json MyApp.dproj --limit:3
```

```
── before.json to MyApp.dproj ──────────────────────────────────────────────────
╭─────────────┬─────────┬─────────╮
│             │   Units │   Edges │
├─────────────┼─────────┼─────────┤
│ before.json │    2378 │   31223 │
│ MyApp.dproj │    2037 │   30331 │
├─────────────┼─────────┼─────────┤
│ change      │    -341 │    -892 │
╰─────────────┴─────────┴─────────╯

Units gone (341)
  Vcl.ActnList, Vcl.Buttons, Vcl.Controls
  ... and 338 more, use --limit:0 for all

References gone (892)
  MyApp.Options uses Vcl.Forms intf MyApp.Options.pas(9)
  MyApp.Options uses Vcl.Graphics intf MyApp.Options.pas(12)
  MyApp.PluginApi uses Vcl.Dialogs impl MyApp.PluginApi.pas(58)
  ... and 889 more, use --limit:0 for all
```

Sections with nothing in them are left out, so a diff that only removed things says only
that.

A dependency that only moved down its file is not a change. One that moved from the
interface to the implementation is.

### Globs

`*` matches any run of characters and `?` matches one, both case insensitively. A name
with no wildcard has to match in full, so `Forms` does not quietly answer for `Vcl.Forms` -
though it will match a unit whose source spelled it that way, since the aliases the
compiler resolved are matched too.

Every command that takes a unit takes a glob, and each reports every matched unit the same
way it would on its own. The exception is the `<from>` of `path`, which has to name one
unit, because a tree needs a root.

## Options

```
  --output:<file>      write the dependency graph as json
  --platform:<name>    Win32, Win64, ... defaults to the project default
  --config:<name>      Debug, Release, ... defaults to the project default
  --compiler:<version> 13, delphi12.0, XE2 ... overrides what the dproj implies
  --define:<a;b>       extra conditional symbols
  --undefine:<a;b>     conditional symbols to remove
  --searchpath:<a;b>   extra unit search paths
  --deep               descend into the Delphi rtl and vcl sources as well
  --maxpaths:<n>       chains to print per unit for why and path (default 5)
  --limit:<n>          rows to print per unit, 0 for all (default 50)
  --depth:<n>          how far down the deps tree to go, 0 for all (default 3)
  --forbid:<a;b>       units check must not reach
  --allow:<a;b>        exceptions to the forbidden units
  --rules:<file>       a file of check rules, one unit name or glob per line
  --quiet              only report errors
```

Every option works with every command.

## Querying a saved graph

Walking a large project takes a moment, so save the graph once and query it as often as
you like. Anything ending in `.json` is read back instead of analysed, and the answers are
identical:

```
DelphiUsesAnalyzer MyApp.dproj --output:graph.json    analysis, ~750ms on a 275 unit project
DelphiUsesAnalyzer why graph.json System.Zip          the same answer, ~47ms
DelphiUsesAnalyzer check graph.json --rules:dua.rules the build gate, no walk at all
```

A saved graph is refused rather than half-read if it is not a graph or its `schemaVersion`
is one this build does not understand. `--output` is ignored when the input is already a
saved graph.

## Progress

The target is worked out and printed first, so a wrong platform or configuration is
obvious immediately rather than after the wait:

```
── Analysing ───────────────────────────────────────────────────────────────────
Project  C:\src\MyApp\MyApp.dproj
Program  C:\src\MyApp\MyApp.dpr
Compiler Delphi 13 Florence delphi13.0
Platform Win32
Config   Debug Application
DProj    ProjectVersion 20.4
Defines  14
Paths    329 search paths
```

The walk then runs behind a live progress bar - spinner, description, bar, percentage and
elapsed time - which clears itself before the summary:

```
⠹ Scanning 1345/3358 units ━━━━━━━━━━━━                    40% 00:00:00
```

The total climbs while the queue is still being discovered, then the bar closes on it.

Live output only happens when the terminal is interactive. Under a pipe, a redirect or CI
there is no bar and no escape sequences at all - captured output is plain text and the
colour is dropped automatically. `--quiet` turns the whole lot off.

## What it does

- **Resolves units the way the compiler does.** Explicit `in` paths from the `.dpr` first,
  then the referencing unit's own folder, then the search paths in order. Unqualified and
  partially qualified names are resolved through the project's unit scope names, so
  `uses Classes` finds `System.Classes` and `uses Generics.Defaults` finds
  `System.Generics.Defaults`.
- **Reads the `.dproj` like msbuild.** Property groups in document order with their
  conditions honoured, so config and platform inheritance comes out right, including the
  `$(DCC_Namespace)` self-reference idiom every dproj uses.
- **Honours DPM.** `$(DPMSearch)` is expanded, so units from packages resolve and are
  tagged `package` in the output.
- **Evaluates conditionals against the target, not the host.** `{$IF CompilerVersion >= 36}`
  is judged against the Delphi the analysed project targets, not the one that built this
  tool. `{$I}` includes are followed so the define set is right.
- **Never silently guesses.** When a condition cannot be evaluated - `{$IF Declared(X)}`,
  `{$IFOPT R+}` - every branch is taken and the edges are tagged `unevaluated`. Losing an
  edge would hide the very dependency you are looking for.
- **Only warns about conditionals that matter.** A warning is raised when an unevaluatable
  `{$IF}` actually guards a uses entry, naming the file, line and expression. The great
  majority of conditionals in real source guard declarations rather than uses clauses, and
  reporting those buries the ones worth reading - on one 2378 unit application that was the
  difference between 54 warnings and none, with an identical graph. `{$IFOPT}` never warns
  at all: compiler switch state says nothing about what a unit uses.
- **Stops at the RTL boundary.** VCL and RTL units are recorded but not opened, because
  their internals are not something you can act on. `--deep` descends anyway.

## Output

Flat nodes and edges, so both "what does this use" and "who uses this" are one pass:

```json
{
  "schemaVersion": 2,
  "project": { "dproj": "...", "dpr": "...", "rootUnit": "SampleApp",
               "compiler": "delphi13.0", "platform": "Win32", "config": "Debug" },
  "defines": ["CONDITIONALEXPRESSIONS", "CONSOLE", "MSWINDOWS", "VER370", "..."],
  "searchPaths": [ { "path": "...", "origin": "project|package|library|rtl" } ],
  "nodes": [ { "name": "Vcl.Graphics", "fileName": "...", "source": "rtl",
               "parsed": false, "aliases": ["Graphics"] } ],
  "edges": [ { "from": "SampleApp.Inner", "to": "Vcl.Graphics", "section": "interface",
               "certainty": "conditional", "condition": "MSWINDOWS",
               "file": "...\\SampleApp.Inner.pas", "line": 7 } ],
  "warnings": [ { "file": "...", "line": 8, "message": "cannot evaluate ..." } ],
  "summary": { "units": 9, "edges": 9, "unresolved": 0, "warnings": 1 }
}
```

A node's `source` is where the unit was found: `program` for the dpr itself, `project`,
`package` for a dpm package, `library` for the IDE library path, `rtl` for anything under
the Delphi installation, or `unresolved`. The console summary folds the program in with the
project units, since there is only ever one of it and the header already names it.

A high `unresolved` count means the search paths are not being assembled correctly - it
should normally be zero.

## Building

Requires Delphi 13 (BDS 37.0) and [DPM](https://github.com/DelphiPackageManager/DPM).

```
dpm restore Source\DelphiUsesAnalyzer.dproj --compiler=13
dpm restore Tests\DelphiUsesAnalyzer.Tests.dproj --compiler=13
build.bat Debug Win32
runtests.bat Win32
```

The scripts look for RAD Studio under Program Files. If yours is elsewhere, point `BDS`
at it first:

```
set BDS=D:\Embarcadero\Studio.0
```

Dependencies, all via DPM: `VSoft.DUnitX`, `VSoft.YAML`, `VSoft.CommandLine`,
`Spring4D.Base` and `VSoft.AnsiConsole` (which brings `VSoft.System.Console` with it).
Everything else is RTL.

## Layout

```
Source/
  DUA.Types                 shared enums and records
  DUA.Defines               the conditional symbol set
  DUA.Conditionals          the {$IF} expression evaluator
  DUA.Scanner               the source scanner - comments, strings, directives, uses
  DUA.Compiler.Versions     Delphi version, platform and predefined symbol tables
  DUA.Compiler.Environment  the installation, its library path and its source tree
  DUA.Project.MSBuild       $(Property) expansion and Condition evaluation
  DUA.Project.DProj         the dproj reader
  DUA.SearchPath            unit name to file, the way the compiler resolves it
  DUA.Graph                 nodes, edges, both indexes and chain finding
  DUA.Graph.Analysis        dominators, cycles, reachability and graph diffing
  DUA.Analyzer              the walk
  DUA.Rules                 the check rules and what breaks them
  DUA.Report.Json           the json output
  DUA.Report.Style          the console vocabulary the reports share
  DUA.Report.Console        target, summary, progress, why, path and references
  DUA.Report.Queries        check, cost, deps, cycles and diff
  DUA.Options               the commands and options
Tests/
  TestData/SampleApp        a fixture whose only route to the vcl is behind an IFDEF
```

The project wide `cost` ranking is a dominator tree, built once per root with Cooper,
Harvey and Kennedy's algorithm, which is what makes it exact rather than a guess and
O(V+E) rather than a search per unit. `cycles` is Kosaraju's. Both walks are iterative
rather than recursive, so a deep graph cannot overflow the stack.

## Performance

Resolution is the hot path: a large project asks the same few units thousands of times
over hundreds of search paths. Three things keep it quick - the candidate names for a used
name are built once rather than per folder, each search path folder is listed once and
answered from memory, and what the search paths said about a name is cached, since they do
not depend on who is asking.

On an application of 2378 units and 31 223 edges across 329 search paths, that was the
difference between **39 seconds and 0.9**, with identical output.

`why` answers from one breadth first search rather than one per unit asked about, so a
survey costs about the same as a single lookup - `why <project> *` on the same project went
from 12.4s to 1.1s.

Once a graph is saved, every query is cheap. On a 275 unit, 2158 edge graph the whole run -
process start, reading the json, answering - is 120 to 190ms for every command, and about
45ms of that is reading the file. The dearest is `cost <project> <unit>`, which runs one
search per dependency the unit has, and even at 230 of them it is 186ms. Nothing here
needs to be run any way other than the obvious one.

## Known limits

- Units inside a DPM package resolve to the `.dcu` in the package's `lib` folder, which is
  what the compiler sees, so the walk stops there rather than descending into the package's
  own dependencies.
- Unit scope resolution does not yet try the referencing unit's own namespace first, which
  the compiler does before falling back to the project scope list.
- The project wide `cost` ranking is much less use on a project whose `.dpr` names every
  unit, which is what the IDE writes when you add one to a project. The program then
  references almost everything directly, so almost nothing is reachable by only one route
  and every unit scores low. That is a true answer rather than a useful one -
  `cost <project> <unit>` and `references` are the questions to ask on such a project.
- Windows only, because it reads the Delphi installation from the registry and
  VSoft.AnsiConsole is a Windows library.
