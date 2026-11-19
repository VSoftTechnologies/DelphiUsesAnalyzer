unit DUA.Report.Style;

{
  The console vocabulary the reports share - escaping, headings, and the grey detail that
  follows a unit name. Kept in one place so the query commands look like the ones that
  were here first rather than nearly like them.
}

interface

uses
  DUA.Types,
  DUA.Graph;

/// <summary>
///   Nothing from a source file or a path can be trusted as markup - a unit path with a
///   bracket in it would otherwise be parsed as a style tag and throw.
/// </summary>
function Safe(const value : string) : string;

/// <summary>
///   "implementation" is fourteen characters of column that a file name needs more, and
///   in a column headed Where the short form is unambiguous.
/// </summary>
function ShortSection(const value : TUsesSection) : string;

/// <summary>
///   Whether there is a terminal to draw on. A live region writes cursor escapes that a
///   redirected file or a pipe would be left holding.
/// </summary>
function Interactive : boolean;

/// <summary>The rule that opens every report section.</summary>
procedure Heading(const title : string);

/// <summary>
///   The condition guarding a dependency, coloured by how sure we are of it. Empty when
///   nothing guards it.
/// </summary>
function GuardLabel(const edge : TGraphEdge) : string;

/// <summary>
///   How the step into a unit was written, so it can be opened and changed. Empty when
///   there is no such dependency.
/// </summary>
function StepLabel(const graph : IUnitGraph; const fromUnit : string;
                   const toUnit : string) : string;

/// <summary>
///   The file name out of a path written with either kind of slash. ExtractFileName only
///   knows about the windows one, and a path typed at a shell often is not.
/// </summary>
function FileNameOnly(const path : string) : string;

/// <summary>
///   What to say when a pattern matched nothing. A glob that caught nothing and a name
///   that is simply not there are different mistakes.
/// </summary>
procedure WriteNotInGraph(const pattern : string);

/// <summary>
///   Whether files are written out in full. One setting for every report, made once
///   before any of them run - a bare file name cannot tell two copies of a unit apart.
/// </summary>
procedure SetFullPaths(const value : boolean);
function FullPaths : boolean;

/// <summary>
///   Where something was written, as File.pas(12), or with the whole path when full paths
///   are on. Escaped, so it can go straight into markup.
/// </summary>
function SourceLocation(const fileName : string; const line : integer) : string;

/// <summary>
///   The file a unit resolved to, escaped, for the units a report is about. Empty when
///   full paths are off or the unit never resolved to a file.
/// </summary>
function ResolvedFile(const node : TGraphNode) : string;

/// <summary>
///   The line under a unit a report is about, naming the file it resolved to. Writes
///   nothing when full paths are off or the unit has no file.
/// </summary>
procedure WriteResolvedFile(const node : TGraphNode; const indent : string);

implementation

uses
  System.SysUtils,
  VSoft.AnsiConsole;

function Safe(const value : string) : string;
begin
  result := AnsiConsole.EscapeMarkup(value);
end;

function FileNameOnly(const path : string) : string;
const
  Separators = ['\', '/'];
var
  index : integer;
begin
  result := path;
  for index := Length(path) downto 1 do
    if CharInSet(path[index], Separators) then
      Exit(Copy(path, index + 1, MaxInt));
end;

function ShortSection(const value : TUsesSection) : string;
begin
  case value of
    usProgram : result := 'prog';
    usInterface : result := 'intf';
  else
    result := 'impl';
  end;
end;

function Interactive : boolean;
begin
  result := AnsiConsole.Profile.Capabilities.Interactive;
end;

procedure Heading(const title : string);
begin
  // a rule title is markup like anything else, and a pattern can contain a bracket
  AnsiConsole.WriteLine(Widgets.Rule(Safe(title)).WithAlignment(TAlignment.Left));
end;

function GuardLabel(const edge : TGraphEdge) : string;
begin
  if edge.Certainty = ecConditional then
    result := Format(' [cyan]%s[/]', [Safe(edge.Condition)])
  else if edge.Certainty = ecUnevaluated then
    result := Format(' [yellow]unevaluated: %s[/]', [Safe(edge.Condition)])
  else
    result := '';
end;

function StepLabel(const graph : IUnitGraph; const fromUnit : string;
  const toUnit : string) : string;
var
  edge : TGraphEdge;
begin
  result := '';
  // only the edges arriving here, rather than every edge in the graph - on a large
  // project that is the difference between a handful of comparisons and thirty thousand
  for edge in graph.EdgesTo(toUnit) do
    if SameText(edge.FromUnit, fromUnit) then
    begin
      result := Format(' [grey]%s %s[/]',
        [Safe(UsesSectionToString(edge.Section)), SourceLocation(edge.FileName, edge.Line)]);
      result := result + GuardLabel(edge);
      Exit;
    end;
end;

procedure WriteNotInGraph(const pattern : string);
begin
  if IsWildcardPattern(pattern) then
    AnsiConsole.MarkupLine('Nothing in the dependency graph matches [yellow]%s[/].',
      [Safe(pattern)])
  else
    AnsiConsole.MarkupLine('[yellow]%s[/] is not in the dependency graph at all.',
      [Safe(pattern)]);
end;

var
  showFullPaths : boolean = false;

procedure SetFullPaths(const value : boolean);
begin
  showFullPaths := value;
end;

function FullPaths : boolean;
begin
  result := showFullPaths;
end;

function SourceLocation(const fileName : string; const line : integer) : string;
begin
  if showFullPaths then
    result := Format('%s(%d)', [Safe(fileName), line])
  else
    result := Format('%s(%d)', [Safe(FileNameOnly(fileName)), line]);
end;

function ResolvedFile(const node : TGraphNode) : string;
begin
  if showFullPaths and (node <> nil) then
    result := Safe(node.FileName)
  else
    result := '';
end;

procedure WriteResolvedFile(const node : TGraphNode; const indent : string);
var
  fileName : string;
begin
  fileName := ResolvedFile(node);
  if fileName <> '' then
    AnsiConsole.MarkupLine(indent + '[grey]' + fileName + '[/]');
end;

end.
