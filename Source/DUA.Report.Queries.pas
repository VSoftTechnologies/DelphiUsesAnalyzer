unit DUA.Report.Queries;

{
  The commands that answer "what would I change" rather than "what is there" - check,
  cost, deps, cycles and diff. Separate from DUA.Report.Console so neither file has
  to be read in full to work on one report.
}

interface

uses
  DUA.Analyzer,
  DUA.Rules;

type
  TQueryReport = record
  public
    /// <summary>
    ///   Rule by rule, whether anything the project reaches breaks it. Returns whether
    ///   everything passed, which is what the exit code is made of - a check nobody can
    ///   fail a build with is just a report.
    /// </summary>
    class function WriteCheck(const analysis : IAnalysisResult; const rules : IRuleSet;
                              const limit : integer) : boolean; static;

    /// <summary>
    ///   What a unit's own uses entries cost, or with no unit, the heaviest units in the
    ///   project. The two answer different questions and the table says which.
    /// </summary>
    class procedure WriteCost(const analysis : IAnalysisResult; const pattern : string;
                              const limit : integer); static;

    /// <summary>
    ///   What a unit drags in, as a tree. A dependency graph drawn as a tree would
    ///   repeat itself endlessly, so a unit is expanded the first time and referred back
    ///   to after that.
    /// </summary>
    class procedure WriteDeps(const analysis : IAnalysisResult; const pattern : string;
                              const depth : integer; const limit : integer); static;

    /// <summary>Groups of units that reference each other, worst first.</summary>
    class procedure WriteCycles(const analysis : IAnalysisResult;
                                const limit : integer); static;

    /// <summary>What changed between two graphs.</summary>
    class procedure WriteDiff(const before : IAnalysisResult; const after : IAnalysisResult;
                              const beforeName : string; const afterName : string;
                              const limit : integer); static;
  end;

implementation

uses
  System.SysUtils,
  Spring.Collections,
  VSoft.AnsiConsole,
  DUA.Types,
  DUA.Graph,
  DUA.Graph.Analysis,
  DUA.Report.Style;

/// <summary>
///   Every name a unit answers to - what the compiler resolved it to, and what the source
///   actually said. A rule written against either is a rule about this unit.
/// </summary>
function NamesOf(const node : TGraphNode) : TArray<string>;
var
  alias : string;
  count : integer;
begin
  SetLength(result, node.Aliases.Count + 1);
  result[0] := node.Name;
  count := 1;
  for alias in node.Aliases do
  begin
    result[count] := alias;
    Inc(count);
  end;
end;

/// <summary>Where a dependency was written, as "File.pas(12)", or empty when unknown.</summary>
function WhereWritten(const graph : IUnitGraph; const fromUnit : string;
  const toUnit : string) : string;
var
  edge : TGraphEdge;
begin
  result := '';
  for edge in graph.EdgesTo(toUnit) do
    if SameText(edge.FromUnit, fromUnit) then
      Exit(Format('%s(%d)', [ExtractFileName(edge.FileName), edge.Line]));
end;

{ check }

class function TQueryReport.WriteCheck(const analysis : IAnalysisResult;
  const rules : IRuleSet; const limit : integer) : boolean;
var
  rule : TUnitRule;
  node : TGraphNode;
  reachable : ISet<string>;
  name : string;
  broken : IList<TGraphNode>;
  chains : IReadOnlyList<TArray<string>>;
  chain : TArray<string>;
  failed : integer;
  shown : integer;
  detail : string;
  via : string;
begin
  AnsiConsole.WriteLine;
  Heading('Checking ' + FileNameOnly(analysis.ProjectFile));

  // A rule is about what the program actually pulls in. A unit sitting in the graph that
  // nothing reaches is not a dependency and should not fail anyone's build.
  reachable := TCollections.CreateSet<string>;
  for name in analysis.Graph.ReachableFrom(analysis.RootUnit) do
    reachable.Add(UpperCase(name));

  failed := 0;
  for rule in rules.Rules do
  begin
    if rule.Allow then
      Continue;

    // each forbidding rule asked on its own, so a rule that catches nothing says so
    // rather than being hidden behind one that caught the same units first
    broken := TCollections.CreateList<TGraphNode>;
    for node in analysis.Graph.Nodes do
    begin
      if SameText(node.Name, analysis.RootUnit) then
        Continue;
      if not reachable.Contains(UpperCase(node.Name)) then
        Continue;
      if rules.Excused(NamesOf(node)) then
        Continue;
      if MatchesUnitPattern(rule.Pattern, node.Name) then
        broken.Add(node)
      else
        for name in node.Aliases do
          if MatchesUnitPattern(rule.Pattern, name) then
          begin
            broken.Add(node);
            Break;
          end;
    end;

    if broken.Count = 0 then
    begin
      AnsiConsole.MarkupLine('[green]PASS[/]  [yellow]%s[/]', [Safe(rule.Pattern)]);
      Continue;
    end;

    Inc(failed);
    if broken.Count = 1 then
      AnsiConsole.MarkupLine('[red]FAIL[/]  [yellow]%s[/] [grey]- 1 unit reaches it[/]',
        [Safe(rule.Pattern)])
    else
      AnsiConsole.MarkupLine('[red]FAIL[/]  [yellow]%s[/] [grey]- %d units reach it[/]',
        [Safe(rule.Pattern), broken.Count]);

    shown := 0;
    for node in broken do
    begin
      if (limit > 0) and (shown >= limit) then
      begin
        AnsiConsole.MarkupLine('      [grey]... and %d more, use --limit:0 for all[/]',
          [broken.Count - shown]);
        Break;
      end;
      Inc(shown);

      // the first step out of the program is the line to go and look at
      via := '';
      detail := '';
      chains := analysis.Graph.FindPaths(analysis.RootUnit, node.Name, 1);
      if chains.Count > 0 then
      begin
        chain := chains[0];
        if Length(chain) > 1 then
        begin
          detail := WhereWritten(analysis.Graph, chain[0], chain[1]);
          // a unit named in the dpr itself is its own first step, so there is no via
          if not SameText(chain[1], node.Name) then
            via := chain[1];
        end;
      end;

      if via <> '' then
        AnsiConsole.MarkupLine('      %s [grey]via[/] %s [grey]%s[/]',
          [Safe(node.Name), Safe(via), Safe(detail)])
      else
        AnsiConsole.MarkupLine('      %s [grey]%s[/]', [Safe(node.Name), Safe(detail)]);
    end;
  end;

  AnsiConsole.WriteLine;
  if rules.ForbidCount = 0 then
    AnsiConsole.MarkupLine('[grey]No rules to check[/]')
  else if (failed = 0) and (rules.ForbidCount = 1) then
    AnsiConsole.MarkupLine('[green]1 rule, passed[/]')
  else if failed = 0 then
    AnsiConsole.MarkupLine('[green]%d rules, all passed[/]', [rules.ForbidCount])
  else if rules.ForbidCount = 1 then
    AnsiConsole.MarkupLine('[red]1 rule, failed[/]')
  else
    AnsiConsole.MarkupLine('[red]%d of %d rules failed[/]', [failed, rules.ForbidCount]);

  result := failed = 0;
end;

{ cost }

/// <summary>
///   What each of a unit's own dependencies costs. Asked of a dependency rather than of
///   an edge, because a unit used from both clauses is still only gone when both go.
/// </summary>
procedure WriteCostOfUnit(const analysis : IAnalysisResult; const unitName : string;
  const limit : integer);
type
  TCostRow = record
    Target : string;
    Exclusive : integer;
    Total : integer;
    Where : string;
  end;
var
  rows : IList<TCostRow>;
  row : TCostRow;
  dependency : string;
  reachableNow : integer;
  table : ITable;
  shown : integer;
begin
  reachableNow := TReach.CountFrom(analysis.Graph, analysis.RootUnit);

  rows := TCollections.CreateList<TCostRow>;
  for dependency in analysis.Graph.Dependencies(unitName) do
  begin
    row := Default(TCostRow);
    row.Target := dependency;
    row.Exclusive := reachableNow -
      TReach.CountWithoutEdge(analysis.Graph, analysis.RootUnit, unitName, dependency);
    row.Total := TReach.CountFrom(analysis.Graph, dependency);
    row.Where := WhereWritten(analysis.Graph, unitName, dependency);
    rows.Add(row);
  end;

  if rows.Count = 0 then
  begin
    AnsiConsole.MarkupLine('[bold yellow]%s[/] [grey]uses nothing[/]', [Safe(unitName)]);
    Exit;
  end;

  rows.Sort(
    function(const left, right : TCostRow) : integer
    begin
      result := right.Exclusive - left.Exclusive;
      if result = 0 then
        result := right.Total - left.Total;
      if result = 0 then
        result := CompareText(left.Target, right.Target);
    end);

  table := Widgets.Table.WithBorder(TTableBorderKind.Rounded);
  table.AddColumn('[bold]Reference[/]', TAlignment.Left);
  table.AddColumn('[bold]Exclusive[/]', TGridColumnWidth.Fixed, 9, TAlignment.Right);
  table.AddColumn('[bold]Total[/]', TGridColumnWidth.Fixed, 5, TAlignment.Right);
  table.AddColumn('[bold]At[/]', TAlignment.Left);

  shown := 0;
  for row in rows do
  begin
    if (limit > 0) and (shown >= limit) then
      Break;
    Inc(shown);
    table.AddRow([Safe(row.Target), IntToStr(row.Exclusive), IntToStr(row.Total),
                  Safe(row.Where)]);
  end;

  AnsiConsole.WriteLine(table);
  if shown < rows.Count then
    AnsiConsole.MarkupLine('[grey]... and %d more, use --limit:0 for all[/]',
      [rows.Count - shown]);

  // two short lines rather than one long one, so it does not wrap whatever the root is
  AnsiConsole.MarkupLine('[grey]Exclusive = units lost from %s if this reference goes[/]',
    [Safe(analysis.RootUnit)]);
  AnsiConsole.MarkupLine('[grey]Total = everything that reference reaches[/]');
end;

/// <summary>Every unit in the project ranked by what only it brings in.</summary>
procedure WriteCostOfProject(const analysis : IAnalysisResult; const limit : integer);
var
  dominators : IDominatorTree;
  ranked : IList<TGraphNode>;
  node : TGraphNode;
  table : ITable;
  shown : integer;
begin
  dominators := TDominators.Build(analysis.Graph, analysis.RootUnit);

  ranked := TCollections.CreateList<TGraphNode>;
  for node in analysis.Graph.Nodes do
  begin
    // the program brings in everything by definition, which is not a finding
    if SameText(node.Name, analysis.RootUnit) then
      Continue;
    if dominators.IsReachable(node.Name) then
      ranked.Add(node);
  end;

  ranked.Sort(
    function(const left, right : TGraphNode) : integer
    begin
      result := dominators.ExclusiveReach(right.Name) - dominators.ExclusiveReach(left.Name);
      if result = 0 then
        result := CompareText(left.Name, right.Name);
    end);

  table := Widgets.Table.WithBorder(TTableBorderKind.Rounded);
  table.AddColumn('[bold]Unit[/]', TAlignment.Left);
  table.AddColumn('[bold]Exclusive[/]', TGridColumnWidth.Fixed, 9, TAlignment.Right);
  table.AddColumn('[bold]Source[/]', TGridColumnWidth.Fixed, 10, TAlignment.Left);

  shown := 0;
  for node in ranked do
  begin
    if (limit > 0) and (shown >= limit) then
      Break;
    Inc(shown);
    table.AddRow([Safe(node.Name), IntToStr(dominators.ExclusiveReach(node.Name)),
                  UnitKindToString(node.Kind)]);
  end;

  AnsiConsole.WriteLine(table);
  if shown < ranked.Count then
    AnsiConsole.MarkupLine('[grey]... and %d more, use --limit:0 for all[/]',
      [ranked.Count - shown]);

  AnsiConsole.MarkupLine('[grey]Exclusive = units that become unreachable from %s if this one goes[/]',
    [Safe(analysis.RootUnit)]);
end;

class procedure TQueryReport.WriteCost(const analysis : IAnalysisResult;
  const pattern : string; const limit : integer);
var
  targets : IReadOnlyList<TGraphNode>;
  target : TGraphNode;
begin
  AnsiConsole.WriteLine;

  if Trim(pattern) = '' then
  begin
    Heading('Heaviest units in ' + analysis.RootUnit);
    WriteCostOfProject(analysis, limit);
    Exit;
  end;

  targets := analysis.Graph.FindNodes(pattern);
  if targets.Count = 0 then
  begin
    WriteNotInGraph(pattern);
    Exit;
  end;

  Heading('What ' + pattern + ' uses costs');
  for target in targets do
  begin
    AnsiConsole.WriteLine;
    AnsiConsole.MarkupLine('[bold yellow]%s[/]', [Safe(target.Name)]);
    WriteCostOfUnit(analysis, target.Name, limit);
  end;
end;

{ deps }

class procedure TQueryReport.WriteDeps(const analysis : IAnalysisResult;
  const pattern : string; const depth : integer; const limit : integer);
var
  targets : IReadOnlyList<TGraphNode>;
  target : TGraphNode;
  tree : ITree;
  expanded : ISet<string>;
  total : integer;
  stoppedShort : boolean;

  procedure Expand(const parent : ITreeNode; const unitName : string; const level : integer);
  var
    dependency : string;
    child : ITreeNode;
    label_ : string;
    shown : integer;
    count : integer;
  begin
    if (depth > 0) and (level > depth) then
    begin
      // there was more below here, so the footnote about the limit is honest
      if analysis.Graph.Dependencies(unitName).Count > 0 then
        stoppedShort := true;
      Exit;
    end;

    shown := 0;
    count := analysis.Graph.Dependencies(unitName).Count;
    for dependency in analysis.Graph.Dependencies(unitName) do
    begin
      if (limit > 0) and (shown >= limit) then
      begin
        parent.AddNode(Format('[grey]... and %d more, use --limit:0 for all[/]',
          [count - shown]));
        Break;
      end;
      Inc(shown);

      label_ := Safe(dependency) +
        StepLabel(analysis.Graph, unitName, dependency);

      // A dependency graph is not a tree, so drawing one as a tree has to stop somewhere.
      // Expanding a unit once and pointing back at it keeps the output the size of the
      // graph rather than the size of every route through it.
      if expanded.Contains(UpperCase(dependency)) then
      begin
        if analysis.Graph.Dependencies(dependency).Count > 0 then
          parent.AddNode(label_ + ' [grey](above)[/]')
        else
          parent.AddNode(label_);
        Continue;
      end;

      expanded.Add(UpperCase(dependency));
      child := parent.AddNode(label_);
      Expand(child, dependency, level + 1);
    end;
  end;

begin
  AnsiConsole.WriteLine;

  targets := analysis.Graph.FindNodes(pattern);
  if targets.Count = 0 then
  begin
    WriteNotInGraph(pattern);
    Exit;
  end;

  Heading('What ' + pattern + ' pulls in');

  for target in targets do
  begin
    AnsiConsole.WriteLine;

    // itself included in the reach, so what it pulls in is one less
    total := TReach.CountFrom(analysis.Graph, target.Name) - 1;
    if total = 1 then
      AnsiConsole.MarkupLine('[bold yellow]%s[/] [grey]pulls in 1 unit[/]', [Safe(target.Name)])
    else
      AnsiConsole.MarkupLine('[bold yellow]%s[/] [grey]pulls in %d units[/]',
        [Safe(target.Name), total]);

    if total = 0 then
      Continue;

    tree := Widgets.Tree(Format('[bold]%s[/]', [Safe(target.Name)]));
    expanded := TCollections.CreateSet<string>;
    expanded.Add(UpperCase(target.Name));
    stoppedShort := false;
    Expand(tree.Root, target.Name, 1);
    AnsiConsole.WriteLine(tree);

    if stoppedShort then
      AnsiConsole.MarkupLine('[grey]Stopped at depth %d, use --depth:0 for all of it[/]',
        [depth]);
  end;
end;

{ cycles }

class procedure TQueryReport.WriteCycles(const analysis : IAnalysisResult;
  const limit : integer);
var
  groups : IReadOnlyList<TArray<string>>;
  group : TArray<string>;
  trip : TArray<string>;
  table : ITable;
  index : integer;
  shown : integer;
  edge : TGraphEdge;
  section : string;
  where : string;
begin
  AnsiConsole.WriteLine;
  Heading('Circular references');

  groups := TCycles.Find(analysis.Graph);
  if groups.Count = 0 then
  begin
    AnsiConsole.MarkupLine('[green]No units reference each other in a circle[/]');
    Exit;
  end;

  if groups.Count = 1 then
    AnsiConsole.MarkupLine('[yellow]1 group of units references itself[/]')
  else
    AnsiConsole.MarkupLine('[yellow]%d groups of units reference themselves[/]',
      [groups.Count]);

  shown := 0;
  for group in groups do
  begin
    if (limit > 0) and (shown >= limit) then
    begin
      AnsiConsole.WriteLine;
      AnsiConsole.MarkupLine('[grey]... and %d more, use --limit:0 for all[/]',
        [groups.Count - shown]);
      Break;
    end;
    Inc(shown);

    trip := TCycles.RoundTripIn(analysis.Graph, group);
    if Length(trip) = 0 then
      Continue;

    AnsiConsole.WriteLine;
    AnsiConsole.MarkupLine('[bold yellow]%d units[/][grey], the shortest way round being[/]',
      [Length(group)]);

    table := Widgets.Table.WithBorder(TTableBorderKind.Rounded);
    table.AddColumn('[bold]Uses[/]', TAlignment.Left);
    table.AddColumn('[bold]Where[/]', TGridColumnWidth.Fixed, 5, TAlignment.Left);
    table.AddColumn('[bold]At[/]', TAlignment.Left);

    for index := 0 to High(trip) - 1 do
    begin
      section := '';
      where := '';
      for edge in analysis.Graph.EdgesTo(trip[index + 1]) do
        if SameText(edge.FromUnit, trip[index]) then
        begin
          section := ShortSection(edge.Section);
          where := Format('%s(%d)%s',
            [ExtractFileName(edge.FileName), edge.Line, GuardLabel(edge)]);
          Break;
        end;

      table.AddRow([Format('%s [grey]uses[/] %s', [Safe(trip[index]), Safe(trip[index + 1])]),
                    section, where]);
    end;

    AnsiConsole.WriteLine(table);
  end;

  AnsiConsole.WriteLine;
  AnsiConsole.MarkupLine('[grey]A circle through implementation clauses compiles, but it makes initialization order matter[/]');
end;

{ diff }

/// <summary>Names on one line, truncated, so a long list does not fill the screen.</summary>
procedure WriteNameList(const heading : string; const names : TArray<string>;
  const limit : integer);
var
  shown : integer;
  index : integer;
  line : string;
begin
  if Length(names) = 0 then
    Exit;

  AnsiConsole.WriteLine;
  AnsiConsole.MarkupLine('[bold]%s[/] [grey](%d)[/]', [Safe(heading), Length(names)]);

  shown := Length(names);
  if (limit > 0) and (shown > limit) then
    shown := limit;

  line := '';
  for index := 0 to shown - 1 do
  begin
    if line <> '' then
      line := line + ', ';
    line := line + Safe(names[index]);
  end;
  AnsiConsole.MarkupLine('  ' + line);

  if shown < Length(names) then
    AnsiConsole.MarkupLine('  [grey]... and %d more, use --limit:0 for all[/]',
      [Length(names) - shown]);
end;

procedure WriteEdgeList(const heading : string; const graph : IUnitGraph;
  const edges : TArray<TGraphEdge>; const limit : integer);
var
  shown : integer;
  index : integer;
begin
  if Length(edges) = 0 then
    Exit;

  AnsiConsole.WriteLine;
  AnsiConsole.MarkupLine('[bold]%s[/] [grey](%d)[/]', [Safe(heading), Length(edges)]);

  shown := Length(edges);
  if (limit > 0) and (shown > limit) then
    shown := limit;

  for index := 0 to shown - 1 do
    AnsiConsole.MarkupLine('  %s [grey]uses[/] %s [grey]%s %s(%d)[/]',
      [Safe(edges[index].FromUnit), Safe(edges[index].ToUnit),
       ShortSection(edges[index].Section),
       Safe(ExtractFileName(edges[index].FileName)), edges[index].Line]);

  if shown < Length(edges) then
    AnsiConsole.MarkupLine('  [grey]... and %d more, use --limit:0 for all[/]',
      [Length(edges) - shown]);
end;

/// <summary>A signed count, so the direction is readable without reading the numbers.</summary>
function Signed(const value : integer) : string;
begin
  if value > 0 then
    result := '[red]+' + IntToStr(value) + '[/]'
  else if value < 0 then
    result := '[green]' + IntToStr(value) + '[/]'
  else
    result := '[grey]0[/]';
end;

class procedure TQueryReport.WriteDiff(const before : IAnalysisResult;
  const after : IAnalysisResult; const beforeName : string; const afterName : string;
  const limit : integer);
var
  delta : TGraphDelta;
  table : ITable;
begin
  AnsiConsole.WriteLine;
  Heading(beforeName + ' to ' + afterName);

  delta := TGraphDiff.Compare(before.Graph, after.Graph);

  table := Widgets.Table.WithBorder(TTableBorderKind.Rounded);
  table.AddColumn('', TAlignment.Left);
  table.AddColumn('[bold]Units[/]', TGridColumnWidth.Fixed, 7, TAlignment.Right);
  table.AddColumn('[bold]Edges[/]', TGridColumnWidth.Fixed, 7, TAlignment.Right);
  table.AddRow([Safe(beforeName), IntToStr(delta.BeforeUnits), IntToStr(delta.BeforeEdges)]);
  table.AddRow([Safe(afterName), IntToStr(delta.AfterUnits), IntToStr(delta.AfterEdges)]);
  table.AddFooter(['[bold]change[/]', Signed(delta.UnitChange), Signed(delta.EdgeChange)]);
  AnsiConsole.WriteLine(table);

  if delta.IsEmpty then
  begin
    AnsiConsole.MarkupLine('[green]The two graphs are the same[/]');
    Exit;
  end;

  WriteNameList('Units gone', delta.RemovedUnits, limit);
  WriteNameList('Units added', delta.AddedUnits, limit);
  WriteEdgeList('References gone', before.Graph, delta.RemovedEdges, limit);
  WriteEdgeList('References added', after.Graph, delta.AddedEdges, limit);
end;

end.
