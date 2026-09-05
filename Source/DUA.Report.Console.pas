unit DUA.Report.Console;

interface

uses
  DUA.Analyzer;

type
  TConsoleReport = record
  public
    /// <summary>
    ///   Run the analysis behind a live progress bar. A large project takes long enough
    ///   that silence looks like a hang. Falls back to running plainly when the terminal
    ///   is not interactive, because a live region writes cursor escapes that a
    ///   redirected file or a pipe would be left holding.
    /// </summary>
    class function RunWithProgress(const analyzer : IAnalyzer; const options : TAnalyzerOptions;
                                   out targetShown : boolean) : IAnalysisResult; static;

    /// <summary>
    ///   What is being analysed and what it is being analysed as. Shown before the walk
    ///   starts, so a wrong platform or configuration is obvious immediately rather than
    ///   after the wait.
    /// </summary>
    class procedure WriteTarget(const analysis : IAnalysisResult); static;

    /// <summary>The progress task description. Separated out so it can be tested.</summary>
    class function ScanDescription(const phase : TAnalyzerPhase; const scanned : integer;
                                   const queued : integer) : string; static;

    class procedure WriteSummary(const analysis : IAnalysisResult); static;
    class procedure WriteElapsed(const milliseconds : Int64; const loadedFrom : string); static;
    class procedure WriteWarnings(const analysis : IAnalysisResult; const maxWarnings : integer); static;

    /// <summary>
    ///   Print the chains from one unit to everything matching a pattern, as a tree.
    ///   Chains share their leading units, so the tree shows where they diverge - which
    ///   is exactly the place worth looking when deciding what to cut. Both why and path
    ///   are this, asked from different places.
    /// </summary>
    class procedure WriteChains(const analysis : IAnalysisResult; const fromUnit : string;
                                const pattern : string; const maxPaths : integer;
                                const title : string); static;

    /// <summary>
    ///   Print the chains from the program to the named unit. The name may be a glob, so
    ///   Vcl.* answers for every vcl unit at once.
    /// </summary>
    class procedure WriteWhy(const analysis : IAnalysisResult; const pattern : string;
                             const maxPaths : integer); static;

    /// <summary>
    ///   The same, but from a unit of your choosing rather than the program - which is
    ///   how you ask whether one part of a project reaches another.
    /// </summary>
    class procedure WritePath(const analysis : IAnalysisResult; const fromPattern : string;
                              const toPattern : string; const maxPaths : integer); static;

    /// <summary>
    ///   The units that reference a unit, with the clause and line of each. A unit named
    ///   directly in the dpr has a one hop chain, so `why` says almost nothing about it -
    ///   this is the question worth asking instead.
    /// </summary>
    class procedure WriteReferences(const analysis : IAnalysisResult; const pattern : string;
                                    const limit : integer); static;
  end;

implementation

uses
  System.SysUtils,
  Spring.Collections,
  VSoft.AnsiConsole,
  DUA.Types,
  DUA.Graph,
  DUA.Report.Style,
  DUA.Compiler.Versions;

{ TConsoleReport }

class function TConsoleReport.ScanDescription(const phase : TAnalyzerPhase;
  const scanned : integer; const queued : integer) : string;
begin
  // the description column is narrow and truncates, so this has to stay short - the
  // bar and percentage carry the rest
  case phase of
    apReadingProject : result := 'Reading project';
    apBuildingSearchPaths : result := 'Building search paths';
    apScanning : result := Format('Scanning %d/%d units', [scanned, scanned + queued]);
  else
    result := Format('Scanned %d units', [scanned]);
  end;
end;

class function TConsoleReport.RunWithProgress(const analyzer : IAnalyzer;
  const options : TAnalyzerOptions; out targetShown : boolean) : IAnalysisResult;
var
  analysis : IAnalysisResult;
  running : TAnalyzerOptions;
begin
  running := options;
  targetShown := false;

  if not Interactive then
  begin
    // no live region, and no progress callback either - there is nowhere to draw it
    running.OnProgress := nil;
    Exit(analyzer.Analyze(running));
  end;

  // Reading the dproj and walking the Delphi source tree for its folders is quick but
  // not instant, so it gets a spinner of its own. Doing it first is what lets the
  // target be printed above the progress bar rather than after it.
  AnsiConsole.Status
    .WithSpinner(TSpinnerKind.Dots)
    .Start('Reading project',
      procedure(const ctx : IStatus)
      begin
        running.OnProgress :=
          procedure(const phase : TAnalyzerPhase; const scanned : integer;
                    const queued : integer; const currentUnit : string)
          begin
            ctx.SetStatus(TConsoleReport.ScanDescription(phase, scanned, queued));
          end;
        analysis := analyzer.Prepare(running);
      end);

  WriteTarget(analysis);
  targetShown := true;

  AnsiConsole.Progress
    .WithAutoClear(true)
    .WithColumns([
      Widgets.SpinnerColumn,
      Widgets.DescriptionColumn,
      Widgets.ProgressBarColumn(30),
      Widgets.PercentageColumn,
      Widgets.ElapsedColumn])
    .Start(
      procedure(const ctx : IProgress)
      var
        task : IProgressTask;
      begin
        task := ctx.AddTask(TConsoleReport.ScanDescription(apReadingProject, 0, 0), 1);
        // until the walk starts there is no total to measure against
        task.IsIndeterminate := true;

        running.OnProgress :=
          procedure(const phase : TAnalyzerPhase; const scanned : integer;
                    const queued : integer; const currentUnit : string)
          begin
            task.Description := TConsoleReport.ScanDescription(phase, scanned, queued);
            if phase = apScanning then
            begin
              task.IsIndeterminate := false;
              // the total only becomes known as the queue is discovered, so it grows
              // for a while before the bar starts closing on it
              task.MaxValue := scanned + queued;
              if task.MaxValue < 1 then
                task.MaxValue := 1;
              task.Value := scanned;
            end
            else if phase = apFinished then
            begin
              task.IsIndeterminate := false;
              task.Value := task.MaxValue;
            end;
          end;

        analyzer.Walk(analysis, running);
      end);

  result := analysis;
end;

class procedure TConsoleReport.WriteTarget(const analysis : IAnalysisResult);
var
  appType : string;
begin
  Heading('Analysing');
  AnsiConsole.MarkupLine('[grey]Project [/] %s', [Safe(analysis.ProjectFile)]);
  AnsiConsole.MarkupLine('[grey]Program [/] %s', [Safe(analysis.DprFile)]);

  AnsiConsole.MarkupLine('[grey]Compiler[/] [cyan]%s[/] [grey]%s[/]',
    [Safe(TCompilerVersions.ToDisplayName(analysis.Compiler)),
     Safe(TCompilerVersions.ToDpmToken(analysis.Compiler))]);
  AnsiConsole.MarkupLine('[grey]Platform[/] [cyan]%s[/]', [Safe(TDelphiPlatforms.ToName(analysis.Platform))]);

  appType := analysis.AppType;
  if appType = '' then
    appType := 'unknown';
  AnsiConsole.MarkupLine('[grey]Config  [/] [cyan]%s[/] [grey]%s[/]', [Safe(analysis.Config), Safe(appType)]);

  // the raw dproj value, since it is what the compiler guess was made from
  if analysis.ProjectVersion <> '' then
    AnsiConsole.MarkupLine('[grey]DProj   [/] [grey]ProjectVersion %s[/]', [Safe(analysis.ProjectVersion)]);

  AnsiConsole.MarkupLine('[grey]Defines [/] [grey]%d[/]', [Length(analysis.Defines.ToArray)]);
  AnsiConsole.MarkupLine('[grey]Paths   [/] [grey]%d search paths[/]', [analysis.Resolver.SearchPaths.Count]);
  AnsiConsole.WriteLine;
end;

class procedure TConsoleReport.WriteSummary(const analysis : IAnalysisResult);
var
  node : TGraphNode;
  counts : IDictionary<string, integer>;
  kind : TUnitKind;
  kindName : string;
  count : integer;
  table : ITable;
begin
  counts := TCollections.CreateDictionary<string, integer>;
  for node in analysis.Graph.Nodes do
  begin
    // The program is named in the header already and there is only ever one of it, so a
    // row of its own says nothing. Counting it as a project unit - which is what a dpr
    // is - keeps the rows adding up to the total.
    if node.Kind = ukProgram then
      kindName := UnitKindToString(ukProject)
    else
      kindName := UnitKindToString(node.Kind);
    counts[kindName] := counts.GetValueOrDefault(kindName, 0) + 1;
  end;

  Heading('Dependency graph');

  table := Widgets.Table.WithBorder(TTableBorderKind.Rounded);
  table.AddColumn('[bold]Source[/]', TAlignment.Left);
  table.AddColumn('[bold]Units[/]', TAlignment.Right);
  for kind := Low(TUnitKind) to High(TUnitKind) do
  begin
    if kind = ukProgram then
      Continue;
    kindName := UnitKindToString(kind);
    if not counts.TryGetValue(kindName, count) then
      Continue;
    // an unresolved unit is the one number worth noticing at a glance
    if kind = ukUnresolved then
      table.AddRow(['[red]' + kindName + '[/]', '[red]' + IntToStr(count) + '[/]'])
    else
      table.AddRow([kindName, IntToStr(count)]);
  end;
  table.AddFooter(['[bold]total[/]', '[bold]' + IntToStr(analysis.Graph.Nodes.Count) + '[/]']);
  AnsiConsole.WriteLine(table);

  AnsiConsole.MarkupLine('[grey]Edges[/] %d', [analysis.Graph.Edges.Count]);

  if analysis.UnresolvedCount > 0 then
    AnsiConsole.MarkupLine('[red]%d units did not resolve[/] [grey]- the search paths are incomplete[/]',
      [analysis.UnresolvedCount]);
  if analysis.Warnings.Count = 1 then
    AnsiConsole.MarkupLine('[yellow]1 warning[/]')
  else if analysis.Warnings.Count > 1 then
    AnsiConsole.MarkupLine('[yellow]%d warnings[/]', [analysis.Warnings.Count]);
end;

class procedure TConsoleReport.WriteElapsed(const milliseconds : Int64; const loadedFrom : string);
begin
  if loadedFrom <> '' then
    AnsiConsole.MarkupLine('[grey]Loaded[/]   %s [grey]in %dms[/]', [Safe(loadedFrom), milliseconds])
  else
    AnsiConsole.MarkupLine('[grey]Elapsed[/]  %dms', [milliseconds]);
end;

class procedure TConsoleReport.WriteWarnings(const analysis : IAnalysisResult;
  const maxWarnings : integer);
var
  warning : TScanWarning;
  shown : integer;
begin
  if analysis.Warnings.Count = 0 then
    Exit;

  AnsiConsole.WriteLine;
  Heading('Warnings');

  shown := 0;
  for warning in analysis.Warnings do
  begin
    if shown >= maxWarnings then
    begin
      AnsiConsole.MarkupLine('[grey]... and %d more[/]', [analysis.Warnings.Count - shown]);
      Break;
    end;

    if warning.Line > 0 then
      AnsiConsole.MarkupLine('[grey]%s[/][grey]([/][yellow]%d[/][grey])[/] %s',
        [Safe(warning.FileName), warning.Line, Safe(warning.Message)])
    else
      AnsiConsole.MarkupLine('[grey]%s[/] %s', [Safe(warning.FileName), Safe(warning.Message)]);
    Inc(shown);
  end;
end;

class procedure TConsoleReport.WriteChains(const analysis : IAnalysisResult;
  const fromUnit : string; const pattern : string; const maxPaths : integer;
  const title : string);
var
  targets : IReadOnlyList<TGraphNode>;
  target : TGraphNode;
  chains : IReadOnlyList<TArray<string>>;
  chain : TArray<string>;
  tree : ITree;
  nodesByPrefix : IDictionary<string, ITreeNode>;
  unreachable : IList<string>;
  parent : ITreeNode;
  child : ITreeNode;
  prefix : string;
  index : integer;
  detail : string;
  name : string;

  function IsATarget(const unitName : string) : boolean;
  var
    candidate : TGraphNode;
  begin
    for candidate in targets do
      if SameText(candidate.Name, unitName) then
        Exit(true);
    result := false;
  end;

begin
  AnsiConsole.WriteLine;

  targets := analysis.Graph.FindNodes(pattern);
  if targets.Count = 0 then
  begin
    WriteNotInGraph(pattern);
    Exit;
  end;

  Heading(title);

  // Every matched unit is answered the same way it would be on its own. Showing fewer
  // routes just because the pattern happened to match more units would mean the same
  // question got two different answers, which is worse than a long tree.
  if targets.Count > 1 then
    AnsiConsole.MarkupLine('[grey]%d units match[/] [yellow]%s[/] [grey](up to %d chains each)[/]',
      [targets.Count, Safe(pattern), maxPaths]);

  tree := Widgets.Tree(Format('[bold]%s[/]', [Safe(fromUnit)]));
  // one node per distinct prefix, so shared leading units are drawn once and the tree
  // shows where the routes actually diverge. Every node gets exactly one parent, which
  // is what keeps the tree renderer happy.
  nodesByPrefix := TCollections.CreateDictionary<string, ITreeNode>;
  unreachable := TCollections.CreateList<string>;

  for target in targets do
  begin
    chains := analysis.Graph.FindPaths(fromUnit, target.Name, maxPaths);
    if chains.Count = 0 then
    begin
      unreachable.Add(target.Name);
      Continue;
    end;

    for chain in chains do
    begin
      parent := tree.Root;
      prefix := '';
      for index := 1 to High(chain) do
      begin
        prefix := prefix + '>' + UpperCase(chain[index]);
        if not nodesByPrefix.TryGetValue(prefix, child) then
        begin
          detail := StepLabel(analysis.Graph, chain[index - 1], chain[index]);
          if IsATarget(chain[index]) then
            child := parent.AddNode(Format('[bold yellow]%s[/]%s', [Safe(chain[index]), detail]))
          else
            child := parent.AddNode(Safe(chain[index]) + detail);
          nodesByPrefix[prefix] := child;
        end;
        parent := child;
      end;
    end;
  end;

  if nodesByPrefix.Count > 0 then
    AnsiConsole.WriteLine(tree);

  if unreachable.Count > 0 then
  begin
    AnsiConsole.WriteLine;
    for name in unreachable do
      AnsiConsole.MarkupLine('[yellow]%s[/] [grey]is in the graph but nothing reaches it from[/] [bold]%s[/]',
        [Safe(name), Safe(fromUnit)]);
  end;
end;

class procedure TConsoleReport.WriteWhy(const analysis : IAnalysisResult;
  const pattern : string; const maxPaths : integer);
begin
  WriteChains(analysis, analysis.RootUnit, pattern, maxPaths, 'Why ' + pattern);
end;

class procedure TConsoleReport.WritePath(const analysis : IAnalysisResult;
  const fromPattern : string; const toPattern : string; const maxPaths : integer);
var
  starts : IReadOnlyList<TGraphNode>;
  candidate : TGraphNode;
begin
  starts := analysis.Graph.FindNodes(fromPattern);

  if starts.Count = 0 then
  begin
    AnsiConsole.WriteLine;
    WriteNotInGraph(fromPattern);
    Exit;
  end;

  // The tree has to be rooted somewhere, so a pattern that could mean several units is
  // a question we cannot answer - naming them is more use than picking one.
  if starts.Count > 1 then
  begin
    AnsiConsole.WriteLine;
    AnsiConsole.MarkupLine('[yellow]%s[/] [grey]matches %d units, so there is no one place to start from[/]',
      [Safe(fromPattern), starts.Count]);
    for candidate in starts do
      AnsiConsole.MarkupLine('  %s', [Safe(candidate.Name)]);
    Exit;
  end;

  WriteChains(analysis, starts[0].Name, toPattern, maxPaths,
    Format('%s to %s', [starts[0].Name, toPattern]));
end;

class procedure TConsoleReport.WriteReferences(const analysis : IAnalysisResult;
  const pattern : string; const limit : integer);
var
  targets : IReadOnlyList<TGraphNode>;
  target : TGraphNode;
  arriving : IReadOnlyList<TGraphEdge>;
  edge : TGraphEdge;
  ordered : IList<TGraphEdge>;
  table : ITable;
  guard : string;
  total : integer;
  shown : integer;
begin
  AnsiConsole.WriteLine;

  targets := analysis.Graph.FindNodes(pattern);
  if targets.Count = 0 then
  begin
    WriteNotInGraph(pattern);
    Exit;
  end;

  Heading('References to ' + pattern);

  total := 0;
  for target in targets do
    total := total + analysis.Graph.EdgesTo(target.Name).Count;

  if targets.Count > 1 then
    AnsiConsole.MarkupLine('[grey]%d units match[/] [yellow]%s[/][grey], referenced %d times[/]',
      [targets.Count, Safe(pattern), total]);

  for target in targets do
  begin
    arriving := analysis.Graph.EdgesTo(target.Name);

    AnsiConsole.WriteLine;
    if arriving.Count = 0 then
    begin
      // the dpr is the obvious case: nothing uses the program, it is the starting point
      AnsiConsole.MarkupLine('[bold yellow]%s[/] [grey]is referenced by nothing[/]', [Safe(target.Name)]);
      Continue;
    end;

    if arriving.Count = 1 then
      AnsiConsole.MarkupLine('[bold yellow]%s[/] [grey]is referenced once[/]', [Safe(target.Name)])
    else
      AnsiConsole.MarkupLine('[bold yellow]%s[/] [grey]is referenced %d times[/]',
        [Safe(target.Name), arriving.Count]);

    // by referencing unit, so the same unit's interface and implementation sit together
    ordered := TCollections.CreateList<TGraphEdge>;
    for edge in arriving do
      ordered.Add(edge);
    ordered.Sort(
      function(const left, right : TGraphEdge) : integer
      begin
        result := CompareText(left.FromUnit, right.FromUnit);
        if result = 0 then
          result := Ord(left.Section) - Ord(right.Section);
      end);

    table := Widgets.Table.WithBorder(TTableBorderKind.Rounded);
    table.AddColumn('[bold]Unit[/]', TAlignment.Left);
    // pinned narrow, otherwise the table hands this column width the file name needs -
    // and a wrapped file name is no use for going and looking at it
    table.AddColumn('[bold]Where[/]', TGridColumnWidth.Fixed, 5, TAlignment.Left);
    table.AddColumn('[bold]At[/]', TAlignment.Left);

    shown := 0;
    for edge in ordered do
    begin
      if (limit > 0) and (shown >= limit) then
        Break;
      Inc(shown);
      guard := GuardLabel(edge);

      table.AddRow([Safe(edge.FromUnit), ShortSection(edge.Section),
        Format('%s(%d)%s', [Safe(ExtractFileName(edge.FileName)), edge.Line, guard])]);
    end;

    AnsiConsole.WriteLine(table);
    if shown < ordered.Count then
      AnsiConsole.MarkupLine('[grey]... and %d more, use --limit:0 for all[/]',
        [ordered.Count - shown]);
  end;
end;

end.
