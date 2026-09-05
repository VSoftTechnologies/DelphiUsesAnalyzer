unit DUA.Report.Json;

interface

uses
  System.SysUtils,
  DUA.Analyzer;

type
  EJsonReportError = class(Exception);

  /// <summary>
  ///   The json representation of an analysis, in both directions. Reading one back is
  ///   what lets --why answer instantly on a large project instead of walking it again.
  /// </summary>
  TJsonReport = record
  public
    /// <summary>
    ///   Nodes and edges rather than a nested tree: the same unit is reached by many
    ///   routes, and a flat form makes both "what does this use" and "who uses this"
    ///   a single pass.
    /// </summary>
    class function Build(const analysis : IAnalysisResult) : string; static;
    class procedure WriteToFile(const analysis : IAnalysisResult; const fileName : string); static;

    /// <summary>
    ///   Read back a graph written by WriteToFile. The result behaves like a fresh
    ///   analysis, so the summary and --why work on it unchanged.
    /// </summary>
    class function Load(const fileName : string) : IAnalysisResult; static;
  end;

implementation

uses
  System.IOUtils,
  VSoft.YAML,
  DUA.Types,
  DUA.Defines,
  DUA.Graph,
  DUA.SearchPath,
  DUA.Compiler.Versions;

const
  /// <summary>
  ///   Bumped whenever the shape below changes incompatibly. 2 renamed a node's "kind"
  ///   to "source", so a graph saved by an earlier build is refused rather than read
  ///   with every unit silently unclassified.
  /// </summary>
  GraphSchemaVersion = 2;

function OriginToString(const origin : TUnitOrigin) : string;
begin
  case origin of
    uoPackage : result := 'package';
    uoLibrary : result := 'library';
    uoRTL : result := 'rtl';
  else
    result := 'project';
  end;
end;

function StringToOrigin(const value : string) : TUnitOrigin;
begin
  if SameText(value, 'package') then
    result := uoPackage
  else if SameText(value, 'library') then
    result := uoLibrary
  else if SameText(value, 'rtl') then
    result := uoRTL
  else
    result := uoProject;
end;

function StringToUnitKind(const value : string) : TUnitKind;
var
  kind : TUnitKind;
begin
  for kind := Low(TUnitKind) to High(TUnitKind) do
    if SameText(UnitKindToString(kind), value) then
      Exit(kind);
  result := ukUnresolved;
end;

function StringToUsesSection(const value : string) : TUsesSection;
var
  section : TUsesSection;
begin
  for section := Low(TUsesSection) to High(TUsesSection) do
    if SameText(UsesSectionToString(section), value) then
      Exit(section);
  result := usInterface;
end;

function StringToEdgeCertainty(const value : string) : TEdgeCertainty;
var
  certainty : TEdgeCertainty;
begin
  for certainty := Low(TEdgeCertainty) to High(TEdgeCertainty) do
    if SameText(EdgeCertaintyToString(certainty), value) then
      Exit(certainty);
  result := ecUnconditional;
end;

function BuildDocument(const analysis : IAnalysisResult) : IYAMLDocument;
var
  root : IYAMLMapping;
  project : IYAMLMapping;
  summary : IYAMLMapping;
  defines : IYAMLSequence;
  searchPaths : IYAMLSequence;
  nodes : IYAMLSequence;
  edges : IYAMLSequence;
  warnings : IYAMLSequence;
  item : IYAMLMapping;
  aliases : IYAMLSequence;
  node : TGraphNode;
  edge : TGraphEdge;
  entry : TSearchPathEntry;
  warning : TScanWarning;
  define : string;
  alias : string;
begin
  result := TYAML.CreateMapping;
  root := result.AsMapping;

  root.AddOrSetValue('schemaVersion', GraphSchemaVersion);

  project := root.AddOrSetMapping('project');
  project.AddOrSetValue('dproj', analysis.ProjectFile);
  project.AddOrSetValue('dpr', analysis.DprFile);
  project.AddOrSetValue('rootUnit', analysis.RootUnit);
  project.AddOrSetValue('compiler', TCompilerVersions.ToDpmToken(analysis.Compiler));
  project.AddOrSetValue('compilerName', TCompilerVersions.ToDisplayName(analysis.Compiler));
  project.AddOrSetValue('platform', TDelphiPlatforms.ToName(analysis.Platform));
  project.AddOrSetValue('config', analysis.Config);
  // both are only for display, so a file written before they existed still loads
  if analysis.AppType <> '' then
    project.AddOrSetValue('appType', analysis.AppType);
  if analysis.ProjectVersion <> '' then
    project.AddOrSetValue('projectVersion', analysis.ProjectVersion);

  defines := root.AddOrSetSequence('defines');
  for define in analysis.Defines.ToArray do
    defines.AddValue(define);

  searchPaths := root.AddOrSetSequence('searchPaths');
  for entry in analysis.Resolver.SearchPaths do
  begin
    item := searchPaths.AddMapping;
    item.AddOrSetValue('path', entry.Path);
    item.AddOrSetValue('origin', OriginToString(entry.Origin));
  end;

  nodes := root.AddOrSetSequence('nodes');
  for node in analysis.Graph.Nodes do
  begin
    item := nodes.AddMapping;
    item.AddOrSetValue('name', node.Name);
    // AddOrSetValue stores an empty string as null, so only write a real path
    if node.FileName <> '' then
      item.AddOrSetValue('fileName', node.FileName)
    else
      item.AddOrSetNull('fileName');
    item.AddOrSetValue('source', UnitKindToString(node.Kind));
    item.AddOrSetValue('parsed', node.Parsed);
    if node.Aliases.Count > 0 then
    begin
      aliases := item.AddOrSetSequence('aliases');
      for alias in node.Aliases do
        aliases.AddValue(alias);
    end;
  end;

  edges := root.AddOrSetSequence('edges');
  for edge in analysis.Graph.Edges do
  begin
    item := edges.AddMapping;
    item.AddOrSetValue('from', edge.FromUnit);
    item.AddOrSetValue('to', edge.ToUnit);
    item.AddOrSetValue('section', UsesSectionToString(edge.Section));
    item.AddOrSetValue('certainty', EdgeCertaintyToString(edge.Certainty));
    if edge.Condition <> '' then
      item.AddOrSetValue('condition', edge.Condition);
    item.AddOrSetValue('file', edge.FileName);
    item.AddOrSetValue('line', edge.Line);
  end;

  warnings := root.AddOrSetSequence('warnings');
  for warning in analysis.Warnings do
  begin
    item := warnings.AddMapping;
    item.AddOrSetValue('file', warning.FileName);
    item.AddOrSetValue('line', warning.Line);
    item.AddOrSetValue('message', warning.Message);
  end;

  summary := root.AddOrSetMapping('summary');
  summary.AddOrSetValue('units', analysis.Graph.Nodes.Count);
  summary.AddOrSetValue('edges', analysis.Graph.Edges.Count);
  summary.AddOrSetValue('unresolved', analysis.UnresolvedCount);
  summary.AddOrSetValue('warnings', analysis.Warnings.Count);
end;

/// <summary>
///   A missing key reads as empty rather than raising, so a file written by a slightly
///   different build still loads as far as it sensibly can.
/// </summary>
function ReadString(const mapping : IYAMLMapping; const key : string) : string;
var
  value : IYAMLValue;
begin
  result := '';
  if (mapping = nil) or not mapping.ContainsKey(key) then
    Exit;
  value := mapping.Items[key];
  if (value = nil) or value.IsNull then
    Exit;
  result := value.AsString;
end;

function ReadInteger(const mapping : IYAMLMapping; const key : string) : integer;
var
  value : IYAMLValue;
begin
  result := 0;
  if (mapping = nil) or not mapping.ContainsKey(key) then
    Exit;
  value := mapping.Items[key];
  if (value = nil) or value.IsNull then
    Exit;
  result := value.AsInteger;
end;

function ReadBoolean(const mapping : IYAMLMapping; const key : string) : boolean;
var
  value : IYAMLValue;
begin
  result := false;
  if (mapping = nil) or not mapping.ContainsKey(key) then
    Exit;
  value := mapping.Items[key];
  if (value = nil) or value.IsNull then
    Exit;
  result := value.AsBoolean;
end;

function ReadSequence(const mapping : IYAMLMapping; const key : string) : IYAMLSequence;
begin
  result := nil;
  if (mapping = nil) or not mapping.ContainsKey(key) then
    Exit;
  if mapping.Items[key].IsNull then
    Exit;
  result := mapping.Items[key].AsSequence;
end;

{ TJsonReport }

class function TJsonReport.Build(const analysis : IAnalysisResult) : string;
begin
  result := TYAML.WriteToJSONString(BuildDocument(analysis));
end;

class procedure TJsonReport.WriteToFile(const analysis : IAnalysisResult; const fileName : string);
begin
  TYAML.WriteToJSONFile(BuildDocument(analysis), fileName);
end;

class function TJsonReport.Load(const fileName : string) : IAnalysisResult;
var
  analysis : TAnalysisResult;
  document : IYAMLDocument;
  root : IYAMLMapping;
  project : IYAMLMapping;
  items : IYAMLSequence;
  item : IYAMLMapping;
  aliases : IYAMLSequence;
  node : TGraphNode;
  edge : TGraphEdge;
  warning : TScanWarning;
  index : integer;
  aliasIndex : integer;
  schemaVersion : integer;
begin
  if not TFile.Exists(fileName) then
    raise EJsonReportError.CreateFmt('graph file not found: %s', [fileName]);

  root := nil;
  try
    document := TYAML.LoadFromFile(fileName);
    if (document <> nil) and (document.Root <> nil) then
      root := document.Root.AsMapping;
  except
    on e : Exception do
      raise EJsonReportError.CreateFmt('%s is not readable json: %s', [fileName, e.Message]);
  end;

  if root = nil then
    raise EJsonReportError.CreateFmt('%s is not a dependency graph', [fileName]);

  // Refuse a shape we do not understand rather than quietly reading half of it and
  // presenting a graph with pieces silently missing.
  if not root.ContainsKey('schemaVersion') then
    raise EJsonReportError.CreateFmt(
      '%s is not a dependency graph, it has no schemaVersion', [fileName]);

  schemaVersion := ReadInteger(root, 'schemaVersion');
  if schemaVersion <> GraphSchemaVersion then
    raise EJsonReportError.CreateFmt(
      '%s uses graph schema version %d, this build understands %d',
      [fileName, schemaVersion, GraphSchemaVersion]);

  if not root.ContainsKey('nodes') then
    raise EJsonReportError.CreateFmt('%s is not a dependency graph, it has no nodes', [fileName]);

  analysis := TAnalysisResult.Create;
  result := analysis;

  if root.ContainsKey('project') and not root.Items['project'].IsNull then
  begin
    project := root.Items['project'].AsMapping;
    analysis.ProjectFile := ReadString(project, 'dproj');
    analysis.DprFile := ReadString(project, 'dpr');
    analysis.RootUnit := ReadString(project, 'rootUnit');
    analysis.Compiler := TCompilerVersions.Parse(ReadString(project, 'compiler'));
    analysis.Platform := TDelphiPlatforms.Parse(ReadString(project, 'platform'));
    analysis.Config := ReadString(project, 'config');
    analysis.AppType := ReadString(project, 'appType');
    analysis.ProjectVersion := ReadString(project, 'projectVersion');
  end;

  analysis.Defines := TDefineSet.Create;
  items := ReadSequence(root, 'defines');
  if items <> nil then
    for index := 0 to items.Count - 1 do
      analysis.Defines.Define(items[index].AsString);

  analysis.Resolver := TUnitResolver.Create;
  items := ReadSequence(root, 'searchPaths');
  if items <> nil then
    for index := 0 to items.Count - 1 do
    begin
      item := items[index].AsMapping;
      analysis.Resolver.AddSearchPath(ReadString(item, 'path'),
        StringToOrigin(ReadString(item, 'origin')));
    end;

  items := ReadSequence(root, 'nodes');
  if items <> nil then
    for index := 0 to items.Count - 1 do
    begin
      item := items[index].AsMapping;
      node := analysis.Graph.EnsureNode(ReadString(item, 'name'));
      node.FileName := ReadString(item, 'fileName');
      node.Kind := StringToUnitKind(ReadString(item, 'source'));
      node.Parsed := ReadBoolean(item, 'parsed');

      aliases := ReadSequence(item, 'aliases');
      if aliases <> nil then
        for aliasIndex := 0 to aliases.Count - 1 do
          node.Aliases.Add(aliases[aliasIndex].AsString);
    end;

  items := ReadSequence(root, 'edges');
  if items <> nil then
    for index := 0 to items.Count - 1 do
    begin
      item := items[index].AsMapping;
      edge := Default(TGraphEdge);
      edge.FromUnit := ReadString(item, 'from');
      edge.ToUnit := ReadString(item, 'to');
      edge.Section := StringToUsesSection(ReadString(item, 'section'));
      edge.Certainty := StringToEdgeCertainty(ReadString(item, 'certainty'));
      edge.Condition := ReadString(item, 'condition');
      edge.FileName := ReadString(item, 'file');
      edge.Line := ReadInteger(item, 'line');
      analysis.Graph.AddEdge(edge);
    end;

  items := ReadSequence(root, 'warnings');
  if items <> nil then
    for index := 0 to items.Count - 1 do
    begin
      item := items[index].AsMapping;
      warning.FileName := ReadString(item, 'file');
      warning.Line := ReadInteger(item, 'line');
      warning.Message := ReadString(item, 'message');
      analysis.Warnings.Add(warning);
    end;
end;

end.
